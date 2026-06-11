import AVFoundation
import Combine
import SwiftUI
import MediaPlayer

/// Thread-safe holder bridging the audio render thread (stream tap) to a consumer
/// such as ShazamKit. The buffer handler is set/cleared on the main actor but
/// invoked from the real-time audio thread.
final class StreamSinkBox: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: ((AVAudioPCMBuffer) -> Void)?

    func set(_ sink: ((AVAudioPCMBuffer) -> Void)?) {
        lock.lock(); self.sink = sink; lock.unlock()
    }

    func call(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let sink = self.sink; lock.unlock()
        sink?(buffer)
    }
}

@MainActor
class RadioPlayer: NSObject, ObservableObject {
    static let shared = RadioPlayer()

    @Published var currentStation: Station?
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTrack: String?
    @Published var currentArtist: String?
    @Published var bufferDuration: Double {
        didSet { UserDefaults.standard.set(bufferDuration, forKey: "buffer_duration") }
    }

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObserver: NSKeyValueObservation?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var interruptionTask: Task<Void, Never>?
    private var wasPlayingBeforeInterruption = false
    private let streamTap = AudioStreamTap()
    /// Receives decoded PCM from the live stream while a tap is active (for ShazamKit).
    let streamSink = StreamSinkBox()
    private var streamTapActive = false
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var artworkToken = 0
    /// Whether `currentTrack` was filled in by ShazamKit (vs. stream metadata). Lets us
    /// drop a stale Shazam title on re-identify without wiping real station metadata.
    private var trackIsFromShazam = false

    private override init() {
        let saved = UserDefaults.standard.double(forKey: "buffer_duration")
        bufferDuration = saved > 0 ? saved : 10.0
        super.init()
        setupAudioSession()
        setupRemoteControls()
        setupInterruptionHandling()
    }

    func play(_ station: Station) {
        if currentStation?.streamURL == station.streamURL, isPlaying { return }
        stop()
        currentStation = station
        currentTrack = nil
        currentArtist = nil
        trackIsFromShazam = false
        isLoading = true

        guard let url = URL(string: station.streamURL) else {
            isLoading = false
            return
        }

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = bufferDuration
        playerItem = item

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput = output
        output.setDelegate(self, queue: .main)
        item.add(output)

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                switch status {
                case .readyToPlay:
                    self?.isLoading = false
                    self?.activateStreamTap()
                case .failed:
                    self?.isLoading = false
                    self?.isPlaying = false
                default:
                    break
                }
            }
        }

        player = AVPlayer(playerItem: item)
        player?.play()
        isPlaying = true
        nowPlayingArtwork = nil
        updateNowPlayingInfo()
        loadArtwork(preferredURL: station.logoURL, initials: station.initials, seed: station.name)
    }

    /// Switches to the next station in the user's list (wraps around). Drives the
    /// CarPlay / lock-screen "next track" control.
    func playNext() {
        let stations = StationsStore.shared.stations
        guard !stations.isEmpty else { return }
        let current = currentStation.flatMap { c in stations.firstIndex(where: { $0.streamURL == c.streamURL }) }
        let nextIndex = ((current ?? -1) + 1) % stations.count
        play(stations[nextIndex])
    }

    /// Switches to the previous station in the user's list (wraps around).
    func playPrevious() {
        let stations = StationsStore.shared.stations
        guard !stations.isEmpty else { return }
        let current = currentStation.flatMap { c in stations.firstIndex(where: { $0.streamURL == c.streamURL }) }
        let prevIndex = ((current ?? 0) - 1 + stations.count) % stations.count
        play(stations[prevIndex])
    }

    func stop() {
        streamTap.remove()
        streamSink.set(nil)
        streamTapActive = false
        player?.pause()
        player = nil
        playerItem = nil
        statusObserver = nil
        metadataOutput = nil
        isPlaying = false
        isLoading = false
        nowPlayingArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        publishWidgetState()
    }

    func togglePlayPause() {
        guard let station = currentStation else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            if player == nil {
                play(station)
            } else {
                player?.play()
                isPlaying = true
            }
        }
        updateNowPlayingInfo()
    }

    /// Attaches a passive MTAudioProcessingTap once the item has audio tracks, routing
    /// decoded PCM to `streamSink`. Retries briefly because stream tracks load late.
    private func activateStreamTap(retriesLeft: Int = 8) {
        guard let item = playerItem, !streamTapActive else { return }
        let box = streamSink
        if streamTap.install(on: item, handler: { buffer, _ in box.call(buffer) }) {
            streamTapActive = true
        } else if retriesLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.playerItem === item else { return }
                self.activateStreamTap(retriesLeft: retriesLeft - 1)
            }
        }
    }

    private func handleMetadata(_ metadata: [AVMetadataItem]) async {
        for item in metadata {
            guard let raw = try? await item.load(.value),
                  let title = (raw as? String) else { continue }
            let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
            // Some stations (e.g. Los 40 Classic) broadcast a bare numeric rotation code in
            // StreamTitle instead of the song. Ignore those so we neither show a meaningless
            // number nor clobber a title ShazamKit already found.
            guard Self.isMeaningfulTitle(cleaned) else { continue }
            let parts = cleaned.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                currentArtist = parts[0]
                currentTrack = parts[1]
            } else {
                currentTrack = cleaned
                currentArtist = nil
            }
            trackIsFromShazam = false
            updateNowPlayingInfo()
            return
        }
    }

    /// A usable on-air title must contain at least one letter. Empty strings or values made
    /// up only of digits/punctuation are station bookkeeping codes, not song names.
    private static func isMeaningfulTitle(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        return s.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default,
                options: [.allowAirPlay, .allowBluetoothHFP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func setupInterruptionHandling() {
        interruptionTask = Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { continue }
                switch type {
                case .began:
                    wasPlayingBeforeInterruption = isPlaying
                    isPlaying = false
                case .ended:
                    guard wasPlayingBeforeInterruption, player != nil else { continue }
                    try? AVAudioSession.sharedInstance().setActive(true)
                    player?.play()
                    isPlaying = true
                    updateNowPlayingInfo()
                @unknown default:
                    break
                }
            }
        }
    }

    private func setupRemoteControls() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTrack ?? currentStation?.name ?? ""
        info[MPMediaItemPropertyArtist] = currentArtist ?? currentStation?.name ?? ""
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        publishWidgetState()
    }

    /// Mirrors the current playback state into the App Group so the widget can show it.
    private func publishWidgetState() {
        if let station = currentStation {
            WidgetShared.saveNowPlaying(NowPlayingSnapshot(
                stationName: station.name,
                track: currentTrack,
                artist: currentArtist,
                logoURL: station.logoURL,
                isPlaying: isPlaying
            ))
        } else {
            WidgetShared.saveNowPlaying(nil)
        }
    }

    /// Enriches the lock screen when ShazamKit identifies the current track.
    func updateNowPlayingFromShazam(title: String, artist: String?, artworkURL: URL?) {
        currentTrack = title
        currentArtist = artist
        trackIsFromShazam = true
        updateNowPlayingInfo()
        loadArtwork(preferredURL: artworkURL?.absoluteString,
                    initials: currentStation?.initials ?? "♪",
                    seed: currentStation?.name ?? title)
    }

    /// Called when the user re-runs identification. Drops a previous Shazam-derived title and
    /// artwork so the screen doesn't keep showing the last song while we listen for the new
    /// one. Real station metadata is left untouched.
    func prepareForReidentify() {
        guard trackIsFromShazam else { return }
        currentTrack = nil
        currentArtist = nil
        trackIsFromShazam = false
        nowPlayingArtwork = nil
        updateNowPlayingInfo()
        if let station = currentStation {
            loadArtwork(preferredURL: station.logoURL, initials: station.initials, seed: station.name)
        }
    }

    /// Loads lock-screen artwork (logo / song art, or drawn initials) off the main thread.
    private func loadArtwork(preferredURL: String?, initials: String, seed: String) {
        artworkToken += 1
        let token = artworkToken
        Task.detached(priority: .utility) {
            let image = await Self.artworkImage(urlString: preferredURL, initials: initials, seed: seed)
            await MainActor.run { [weak self] in
                guard let self, token == self.artworkToken else { return }
                self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.updateNowPlayingInfo()
            }
        }
    }

    private nonisolated static func artworkImage(urlString: String?, initials: String, seed: String) async -> UIImage {
        if let raw = urlString, let url = URL(string: raw),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let image = UIImage(data: data) {
            return image
        }
        return drawInitialsImage(initials, seed: seed)
    }

    /// Renders a colored 512×512 tile with the station initials — a graceful artwork fallback.
    private nonisolated static func drawInitialsImage(_ initials: String, seed: String) -> UIImage {
        let palette: [UIColor] = [.systemRed, .systemOrange, .systemBlue, .systemPurple,
                                  .systemGreen, .systemPink, .systemIndigo, .systemTeal]
        let index = ((seed.hashValue % palette.count) + palette.count) % palette.count
        let color = palette[index]
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            color.withAlphaComponent(0.22).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 220, weight: .bold),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
            let text = initials as NSString
            let textHeight = text.size(withAttributes: attrs).height
            let rect = CGRect(x: 0, y: (size.height - textHeight) / 2, width: size.width, height: textHeight)
            text.draw(in: rect, withAttributes: attrs)
        }
    }
}

extension RadioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        let items = groups.flatMap { $0.items }
        Task { @MainActor in await self.handleMetadata(items) }
    }
}
