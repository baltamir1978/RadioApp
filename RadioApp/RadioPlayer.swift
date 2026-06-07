import AVFoundation
import Combine
import SwiftUI
import MediaPlayer

@MainActor
class RadioPlayer: NSObject, ObservableObject {
    static let shared = RadioPlayer()

    @Published var currentStation: Station?
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTrack: String?
    @Published var currentArtist: String?

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObserver: NSKeyValueObservation?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var interruptionTask: Task<Void, Never>?
    private var wasPlayingBeforeInterruption = false
    private let streamTap = AudioStreamTap()

    private override init() {
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
        isLoading = true

        guard let url = URL(string: station.streamURL) else {
            isLoading = false
            return
        }

        let item = AVPlayerItem(url: url)
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
        updateNowPlayingInfo()
    }

    func stop() {
        streamTap.remove()
        player?.pause()
        player = nil
        playerItem = nil
        statusObserver = nil
        metadataOutput = nil
        isPlaying = false
        isLoading = false
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

    /// Install a passive stream tap on the current player item.
    /// Returns false if no item is loaded or tracks aren't ready yet.
    @discardableResult
    func installStreamTap(handler: @escaping (AVAudioPCMBuffer, AVAudioTime?) -> Void) -> Bool {
        guard let item = playerItem else { return false }
        return streamTap.install(on: item, handler: handler)
    }

    func removeStreamTap() {
        streamTap.remove()
    }

    private func handleMetadata(_ metadata: [AVMetadataItem]) async {
        for item in metadata {
            guard let raw = try? await item.load(.value),
                  let title = raw as? String else { continue }
            let parts = title.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                currentArtist = parts[0]
                currentTrack = parts[1]
            } else {
                currentTrack = title
                currentArtist = nil
            }
            updateNowPlayingInfo()
            return
        }
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
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTrack ?? currentStation?.name ?? ""
        info[MPMediaItemPropertyArtist] = currentArtist ?? currentStation?.name ?? ""
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
