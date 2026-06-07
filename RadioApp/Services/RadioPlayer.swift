import AVFoundation
import MediaPlayer
import Combine

final class RadioPlayer: ObservableObject {
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
    private var statusObserver: NSKeyValueObservation?
    private var prefetchedItems: [UUID: AVPlayerItem] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        let saved = UserDefaults.standard.double(forKey: "buffer_duration")
        bufferDuration = saved > 0 ? saved : 10.0
        setupAudioSession()
        setupRemoteControls()
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

        metadata.attach(to: item)
        observeStatus(of: item)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        updateNowPlaying(station: station)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        isLoading = false
        statusObserver = nil
        metadata.detach()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func toggle() {
        if isPlaying { stop() } else if let station = currentStation { play(station) }
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

    private func updateNowPlaying(station: Station) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: station.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue,
        ]
        if let image = UIImage(named: "NowPlayingArtwork") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
