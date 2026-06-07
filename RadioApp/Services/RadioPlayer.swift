import AVFoundation
import MediaPlayer
import Combine
import UIKit

final class RadioPlayer: ObservableObject {
    /// Single shared instance driving both the SwiftUI app and the CarPlay scene.
    static let shared = RadioPlayer()

    /// Title/artist/art currently shown on the lock screen (from ICY metadata or Shazam).
    private struct TrackInfo {
        var title: String
        var artist: String?
        var artworkURL: String?
    }

    @Published var currentStation: Station?
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var bufferDuration: Double {
        didSet { UserDefaults.standard.set(bufferDuration, forKey: "buffer_duration") }
    }

    let metadata = MetadataService()

    /// Emits (stationName, rawICYTitle) when the stream reports a stable new track.
    var newICYTrackPublisher: AnyPublisher<(Station, String), Never> {
        metadata.stableTrackPublisher
            .compactMap { [weak self] title -> (Station, String)? in
                guard let station = self?.currentStation else { return nil }
                return (station, title)
            }
            .eraseToAnyPublisher()
    }

    private let player = AVPlayer()
    private let streamTap = AudioStreamTap()
    private var statusObserver: NSKeyValueObservation?
    private var prefetchedItems: [UUID: AVPlayerItem] = [:]
    private var cancellables = Set<AnyCancellable>()

    private var currentTrack: TrackInfo?
    private var currentArtwork: MPMediaItemArtwork?
    private var artworkToken = 0

    init() {
        let saved = UserDefaults.standard.double(forKey: "buffer_duration")
        bufferDuration = saved > 0 ? saved : 10.0
        setupAudioSession()
        setupRemoteControls()

        // Reflect live stream (ICY) metadata on the lock screen as it changes.
        metadata.$streamTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in self?.handleICYTitle(title) }
            .store(in: &cancellables)
    }

    // MARK: - Playback

    func play(_ station: Station) {
        isLoading = true
        currentStation = station

        let item: AVPlayerItem
        if let prefetched = prefetchedItems[station.id] {
            item = prefetched
            prefetchedItems.removeValue(forKey: station.id)
        } else {
            item = makeItem(for: station)
        }

        currentTrack = nil
        currentArtwork = nil
        metadata.attach(to: item)
        observeStatus(of: item)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        refreshNowPlaying()
    }

    func stop() {
        streamTap.remove()
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        isLoading = false
        statusObserver = nil
        metadata.detach()
        currentTrack = nil
        currentArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func toggle() {
        if isPlaying { stop() } else if let station = currentStation { play(station) }
    }

    // MARK: - Song-recognition stream tap

    /// Installs a passive PCM tap on the current stream so ShazamKit can listen to
    /// the decoded audio directly (works with headphones/AirPlay, no microphone).
    /// Returns false if there is no playing item with audio tracks yet.
    @discardableResult
    func installStreamTap(_ handler: @escaping (AVAudioPCMBuffer, AVAudioTime?) -> Void) -> Bool {
        guard let item = player.currentItem else { return false }
        return streamTap.install(on: item, handler: handler)
    }

    func removeStreamTap() {
        streamTap.remove()
    }

    // MARK: - Pre-fetch next station

    func prefetch(_ station: Station) {
        guard prefetchedItems[station.id] == nil else { return }
        prefetchedItems[station.id] = makeItem(for: station)
    }

    func clearPrefetch() {
        prefetchedItems.removeAll()
    }

    // MARK: - Private helpers

    private func makeItem(for station: Station) -> AVPlayerItem {
        guard let url = URL(string: station.url) else {
            fatalError("Invalid URL for station \(station.name)")
        }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = bufferDuration
        return item
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay: self?.isLoading = false
                case .failed:
                    self?.isLoading = false
                    self?.isPlaying = false
                default: break
                }
            }
        }
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession error: \(error)")
        }
    }

    // MARK: - Lock screen & Control Center

    private func setupRemoteControls() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget  { [weak self] _ in self?.toggle(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        center.stopCommand.addTarget  { [weak self] _ in self?.stop();   return .success }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    /// Call when ShazamKit identifies the current track, to enrich the lock screen.
    func updateNowPlayingFromShazam(title: String, artist: String?, artworkURL: URL?) {
        currentTrack = TrackInfo(title: title, artist: artist, artworkURL: artworkURL?.absoluteString)
        refreshNowPlaying()
    }

    private func handleICYTitle(_ title: String?) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            // Keep a Shazam result if we already have one; otherwise show just the station.
            if currentTrack?.artworkURL == nil { currentTrack = nil; refreshNowPlaying() }
            return
        }
        let (parsedTitle, parsedArtist) = Self.parseICY(trimmed)
        currentTrack = TrackInfo(title: parsedTitle, artist: parsedArtist, artworkURL: nil)
        refreshNowPlaying()
    }

    /// Splits an "Artist - Title" ICY string; falls back to the whole string as title.
    private static func parseICY(_ raw: String) -> (title: String, artist: String?) {
        let parts = raw.components(separatedBy: " - ")
        if parts.count >= 2 {
            let artist = parts[0].trimmingCharacters(in: .whitespaces)
            let title = parts[1...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            return (title, artist)
        }
        return (raw, nil)
    }

    private func refreshNowPlaying() {
        guard let station = currentStation else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue,
        ]
        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.title
            info[MPMediaItemPropertyArtist] = track.artist ?? station.name
            info[MPMediaItemPropertyAlbumTitle] = station.name
        } else {
            info[MPMediaItemPropertyTitle] = station.name
        }
        if let artwork = currentArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        loadArtwork(preferredURL: currentTrack?.artworkURL ?? station.logoURL,
                    initials: station.initials,
                    seed: station.name)
    }

    /// Loads the lock-screen artwork (song/station logo, or drawn initials) off the main thread.
    private func loadArtwork(preferredURL: String?, initials: String, seed: String) {
        artworkToken += 1
        let token = artworkToken
        Task.detached(priority: .utility) {
            let image = await Self.artworkImage(urlString: preferredURL, initials: initials, seed: seed)
            await MainActor.run { [weak self] in
                guard let self, token == self.artworkToken else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.currentArtwork = artwork
                if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
    }

    private static func artworkImage(urlString: String?, initials: String, seed: String) async -> UIImage {
        if let raw = urlString, let url = URL(string: raw),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let image = UIImage(data: data) {
            return image
        }
        return drawInitialsImage(initials, seed: seed)
    }

    /// Renders a colored 512×512 tile with the station initials — a graceful artwork fallback.
    private static func drawInitialsImage(_ initials: String, seed: String) -> UIImage {
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
