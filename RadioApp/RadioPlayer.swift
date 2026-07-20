import AVFoundation
import Combine
import SwiftUI
import MediaPlayer
import Network
import os

/// Playback / reconnection tracing. Visible in Console.app (and `xcrun simctl spawn … log stream`)
/// under subsystem `com.radioapp.playback` — the only practical way to see why a stream failed to
/// start while driving, since the symptom (silent play/pause flicker) looks identical whatever the cause.
private let playbackLog = Logger(subsystem: "com.radioapp.playback", category: "stream")

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
    /// Cover art URL for the track on screen — a real album cover when we have one, else nil
    /// (the UI falls back to the station logo). Filled from ShazamKit directly, or looked up
    /// by artist+title for stations that only broadcast an ICY title.
    @Published var currentArtworkURL: URL?
    /// Apple Music link for the current track, whatever the source. Powers the lyrics link-out.
    @Published var currentAppleMusicURL: URL?
    /// True while we are rebuilding a dropped connection. Lets the UI show "Reconnecting…"
    /// instead of a dead Play button.
    @Published var isReconnecting = false
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
    /// "artist|title" of the last resolved cover, so repeated ICY frames for the same song
    /// don't re-hit the network. Bumped independently of `artworkToken` (image-load race).
    private var lastArtworkKey: String?
    private var artworkResolveToken = 0
    /// Whether `currentTrack` was filled in by ShazamKit (vs. stream metadata). Lets us
    /// drop a stale Shazam title on re-identify without wiping real station metadata.
    private var trackIsFromShazam = false

    // MARK: Reconnection
    /// True while the user wants audio. Survives transient network drops so the watchdog
    /// knows to keep rebuilding the connection. Distinct from `isPlaying`, which tracks
    /// whether audio is actually coming out right now.
    private var intendsToPlay = false
    private var timeControlObserver: NSKeyValueObservation?
    /// Per-item NotificationCenter tokens (stall / failed-to-end), removed on teardown.
    private var itemObservers: [NSObjectProtocol] = []
    private var watchdogTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let pathMonitor = NWPathMonitor()
    private var hasNetwork = true
    /// How long established playback may sit stalled before we rebuild the connection.
    private let stallGrace: TimeInterval = 5
    /// How long a *fresh* connection may sit buffering before we give up on it. Far longer than
    /// `stallGrace`: filling `preferredForwardBufferDuration` on a slow cellular link legitimately
    /// takes more than a few seconds, and tearing it down at 5s means the stream never starts at all.
    private let connectGrace: TimeInterval = 25
    /// Whether the current connection ever reached `.playing`. Distinguishes "still connecting"
    /// from "was playing and dropped", which need very different patience.
    private var hasPlayedSinceConnect = false
    /// Upper bound on the exponential backoff between reconnect attempts.
    private let maxReconnectDelay: TimeInterval = 15

    // MARK: Make-before-break (silent early reconnect)
    /// Watches `isPlaybackLikelyToKeepUp` on the live item — the earliest hint that fresh data
    /// stopped arriving, while the buffer is still draining and audio still plays.
    private var bufferHealthObserver: NSKeyValueObservation?
    /// A second connection opened in parallel while the current one is still playing its buffer.
    /// Promoted (swapped in) once ready, so recovery has no silent gap.
    private var standbyItem: AVPlayerItem?
    /// The standby item needs its own (muted, never-played) AVPlayer: an AVPlayerItem that isn't
    /// attached to a player never starts loading, so its status would sit at `.unknown` forever.
    private var standbyPlayer: AVPlayer?
    private var standbyStatusObserver: NSKeyValueObservation?
    private var standbyTimeoutTask: Task<Void, Never>?
    /// Loopback proxies feeding the live and standby items; each lives as long as its item.
    private var streamProxy: LocalStreamProxy?
    private var standbyProxy: LocalStreamProxy?
    /// How long a standby connection may take to become ready before we drop it and fall back to
    /// the reactive watchdog. Without this a hung standby would block every later preflight.
    private let standbyTimeout: TimeInterval = 20
    private var preflightTask: Task<Void, Never>?
    /// Grace after a buffer-health dip before we open the standby connection. Absorbs the brief
    /// `isPlaybackLikelyToKeepUp` flicker that's normal on 5G, so we don't reconnect needlessly.
    private let preflightGrace: TimeInterval = 1.5

    private override init() {
        let saved = UserDefaults.standard.double(forKey: "buffer_duration")
        bufferDuration = saved > 0 ? saved : 10.0
        super.init()
        setupAudioSession()
        setupRemoteControls()
        setupInterruptionHandling()
        setupPathMonitor()
    }

    func play(_ station: Station) {
        if currentStation?.streamURL == station.streamURL, isPlaying { return }
        stop()
        currentStation = station
        currentTrack = nil
        currentArtist = nil
        currentArtworkURL = nil
        currentAppleMusicURL = nil
        lastArtworkKey = nil
        trackIsFromShazam = false
        isLoading = true
        intendsToPlay = true
        reconnectAttempt = 0

        guard startStream() else {
            isLoading = false
            intendsToPlay = false
            return
        }

        nowPlayingArtwork = nil
        updateNowPlayingInfo()
        loadArtwork(preferredURL: station.logoURL, initials: station.initials, seed: station.name)
    }

    /// Builds a fresh player item from `currentStation` and starts it. Shared by the initial
    /// `play(_:)` and every reconnect attempt. Returns false only if the URL is unusable.
    @discardableResult
    private func startStream() -> Bool {
        guard let station = currentStation, let url = URL(string: station.streamURL) else { return false }

        let (item, proxy) = makeItem(for: url)
        playerItem = item
        streamProxy?.stop()
        streamProxy = proxy
        hasPlayedSinceConnect = false

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput = output
        output.setDelegate(self, queue: .main)
        item.add(output)

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in self?.handleItemStatus(status) }
        }
        attachStallObservers(to: item)
        observeBufferHealth(of: item)

        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        observeTimeControl(of: player)
        player.play()
        isPlaying = true
        return true
    }

    /// Builds a player item for a stream URL. Continuous live audio goes through
    /// `LocalStreamProxy`, which relays it without byte-range requests — some broadcast servers
    /// answer those with an overflowed length that AVPlayer can't play at all (see that class).
    /// HLS keeps AVFoundation's own stack, which genuinely needs range access; and if the proxy
    /// can't start for any reason we fall back to playing the URL directly.
    private func makeItem(for url: URL) -> (AVPlayerItem, LocalStreamProxy?) {
        let item: AVPlayerItem
        var proxy: LocalStreamProxy?
        if url.pathExtension.lowercased() != "m3u8",
           let live = LocalStreamProxy(originURL: url), let localURL = live.localURL {
            item = AVPlayerItem(url: localURL)
            proxy = live
        } else {
            item = AVPlayerItem(url: url)
        }
        item.preferredForwardBufferDuration = bufferDuration
        return (item, proxy)
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            isLoading = false
        case .failed:
            playbackLog.error("item failed: \(String(describing: self.playerItem?.error), privacy: .public)")
            // A live stream that errors out won't recover on its own — rebuild it.
            if intendsToPlay {
                scheduleReconnect()
            } else {
                isLoading = false
                isPlaying = false
            }
        default:
            break
        }
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
        intendsToPlay = false
        cancelReconnect()
        teardownStream()
        isPlaying = false
        isLoading = false
        nowPlayingArtwork = nil
        currentArtworkURL = nil
        currentAppleMusicURL = nil
        lastArtworkKey = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        publishWidgetState()
    }

    /// Disposes the AVPlayer and its observers without touching the chosen station, the user's
    /// intent to play, or the reconnect schedule — used between reconnect attempts and by `stop`.
    private func teardownStream() {
        cancelPreflight()
        bufferHealthObserver = nil
        streamTap.remove()
        streamSink.set(nil)
        streamTapActive = false
        timeControlObserver = nil
        statusObserver = nil
        for token in itemObservers { NotificationCenter.default.removeObserver(token) }
        itemObservers = []
        player?.pause()
        player = nil
        playerItem = nil
        metadataOutput = nil
        streamProxy?.stop()
        streamProxy = nil
    }

    func togglePlayPause() {
        guard let station = currentStation else { return }
        if isPlaying || isReconnecting {
            intendsToPlay = false
            cancelReconnect()
            player?.pause()
            isPlaying = false
        } else {
            intendsToPlay = true
            if player == nil {
                play(station)
            } else {
                player?.play()
                isPlaying = true
            }
        }
        updateNowPlayingInfo()
    }

    // MARK: - Reconnection

    /// Watches for buffer-empty stalls and play-to-end failures on the live item. Both mean the
    /// connection died and AVPlayer won't resume by itself, so we arm the reconnect watchdog.
    private func attachStallObservers(to item: AVPlayerItem) {
        let center = NotificationCenter.default
        let stalled = center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.armWatchdog() }
        }
        let failed = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
            Task { @MainActor [weak self] in
                playbackLog.error("failed-to-play-to-end: \(String(describing: err), privacy: .public)")
                self?.scheduleReconnect()
            }
        }
        itemObservers = [stalled, failed]
    }

    /// Tracks the player's time-control status. A live stream that drops parks in
    /// `.waitingToPlayAtSpecifiedRate`; if it lingers there we rebuild the connection. Reaching
    /// `.playing` means a (re)connect succeeded, so we clear the backoff and the spinner.
    private func observeTimeControl(of player: AVPlayer) {
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in self?.handleTimeControl(status) }
        }
    }

    private func handleTimeControl(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            if !hasPlayedSinceConnect { playbackLog.notice("playing — audio started") }
            isLoading = false
            isReconnecting = false
            reconnectAttempt = 0
            hasPlayedSinceConnect = true
            disarmWatchdog()
        case .waitingToPlayAtSpecifiedRate:
            if intendsToPlay { armWatchdog() }
        case .paused:
            disarmWatchdog()
        @unknown default:
            break
        }
    }

    /// One-shot timer: if the stream still isn't playing after the applicable grace, reconnect.
    /// Idempotent — repeated stall signals won't pile up timers.
    private func armWatchdog() {
        guard intendsToPlay, watchdogTask == nil else { return }
        // A connection that has never played is still buffering, not stalled — give it room.
        let grace = hasPlayedSinceConnect ? stallGrace : connectGrace
        watchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
            self.watchdogTask = nil
            guard !Task.isCancelled, self.intendsToPlay else { return }
            if self.player?.timeControlStatus != .playing {
                playbackLog.notice("watchdog fired after \(grace, privacy: .public)s (hasPlayed=\(self.hasPlayedSinceConnect, privacy: .public)) → reconnect")
                self.scheduleReconnect()
            }
        }
    }

    private func disarmWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    /// Tears down the stalled player and rebuilds it after an exponential backoff (capped at
    /// `maxReconnectDelay`). Re-entrant safe: an in-flight attempt is cancelled and rescheduled.
    private func scheduleReconnect() {
        guard intendsToPlay else { return }
        disarmWatchdog()
        reconnectTask?.cancel()
        isReconnecting = true

        let delay = min(pow(2, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1

        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.reconnectTask = nil
            guard !Task.isCancelled, self.intendsToPlay else { return }
            // No point rebuilding while the network is down; the path monitor will kick us
            // the moment connectivity returns.
            guard self.hasNetwork else { return }
            playbackLog.notice("rebuilding connection (attempt \(self.reconnectAttempt, privacy: .public))")
            self.teardownStream()
            self.startStream()
        }
    }

    private func cancelReconnect() {
        disarmWatchdog()
        cancelPreflight()
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        reconnectAttempt = 0
    }

    private func setupPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in self?.handleNetworkChange(satisfied: satisfied) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "radio.path.monitor"))
    }

    /// Recovers instantly when connectivity returns (e.g. leaving a tunnel) instead of waiting
    /// out the backoff. Only acts while already reconnecting, so it never disturbs healthy playback.
    private func handleNetworkChange(satisfied: Bool) {
        hasNetwork = satisfied
        guard satisfied, intendsToPlay, isReconnecting else { return }
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        scheduleReconnect()
    }

    // MARK: Make-before-break

    /// Observes the playing item's buffer health. `isPlaybackLikelyToKeepUp` flips false the
    /// instant fresh data stops arriving — earlier than any stall, while audio still plays from
    /// the remaining buffer. That head start is what lets us reconnect silently.
    private func observeBufferHealth(of item: AVPlayerItem) {
        bufferHealthObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            let likely = item.isPlaybackLikelyToKeepUp
            Task { @MainActor [weak self] in self?.handleBufferHealth(likelyToKeepUp: likely) }
        }
    }

    private func handleBufferHealth(likelyToKeepUp likely: Bool) {
        if likely {
            // Buffer refilled on its own — it was just a flicker; abandon the pending standby.
            cancelPreflight()
        } else {
            startPreflight()
        }
    }

    /// After a buffer dip survives `preflightGrace`, opens a standby connection in the background.
    /// Guards on `timeControlStatus == .playing` so this never fires during the initial connect
    /// (when the buffer is legitimately not yet full).
    private func startPreflight() {
        guard intendsToPlay, hasNetwork, !isReconnecting,
              standbyItem == nil, preflightTask == nil,
              player?.timeControlStatus == .playing else { return }
        preflightTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.preflightGrace * 1_000_000_000))
            self.preflightTask = nil
            // Still struggling after the grace (not a flicker) and nothing else already handling it?
            guard !Task.isCancelled, self.intendsToPlay, self.hasNetwork, !self.isReconnecting,
                  self.standbyItem == nil,
                  self.player?.currentItem?.isPlaybackLikelyToKeepUp == false else { return }
            self.buildStandby()
        }
    }

    private func cancelPreflight() {
        preflightTask?.cancel()
        preflightTask = nil
        discardStandby()
    }

    /// Opens a second connection to the same stream without touching the audio that's still
    /// playing. When it reaches `.readyToPlay` we swap it in; if it fails, we drop it and let the
    /// reactive stall watchdog take over.
    private func buildStandby() {
        guard let station = currentStation, let url = URL(string: station.streamURL) else { return }
        let (item, proxy) = makeItem(for: url)
        standbyItem = item
        standbyProxy = proxy
        standbyStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                switch status {
                case .readyToPlay: self?.promoteStandby()
                case .failed: self?.discardStandby()
                default: break
                }
            }
        }
        // Attaching to a player is what actually opens the connection. It stays muted and paused,
        // so the buffer fills silently underneath the audio still coming from the primary.
        let warmup = AVPlayer(playerItem: item)
        warmup.isMuted = true
        warmup.automaticallyWaitsToMinimizeStalling = true
        standbyPlayer = warmup

        standbyTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.standbyTimeout * 1_000_000_000))
            guard !Task.isCancelled, self.standbyItem === item else { return }
            self.discardStandby()
        }
    }

    /// Swaps the ready standby item in for the struggling primary. The old buffer covers playback
    /// right up to the swap, so there's no silent stall — at most a small jump to the live edge.
    private func promoteStandby() {
        guard intendsToPlay, let player, let standby = standbyItem else { discardStandby(); return }

        // Detach the dying primary's observers / metadata / tap.
        bufferHealthObserver = nil
        statusObserver = nil
        for token in itemObservers { NotificationCenter.default.removeObserver(token) }
        itemObservers = []
        streamTap.remove()
        streamSink.set(nil)
        streamTapActive = false

        // Hand the standby its own metadata output and observers, then make it current.
        standbyStatusObserver = nil
        standbyTimeoutTask?.cancel()
        standbyTimeoutTask = nil
        standbyItem = nil
        // An item can only belong to one player — release it from the warm-up player first.
        standbyPlayer?.replaceCurrentItem(with: nil)
        standbyPlayer = nil
        // The standby's proxy now backs the live item; the outgoing one can go.
        streamProxy?.stop()
        streamProxy = standbyProxy
        standbyProxy = nil
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput = output
        output.setDelegate(self, queue: .main)
        standby.add(output)
        playerItem = standby
        statusObserver = standby.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in self?.handleItemStatus(status) }
        }
        attachStallObservers(to: standby)
        observeBufferHealth(of: standby)

        player.replaceCurrentItem(with: standby)
        player.play()
        isPlaying = true
        isReconnecting = false
        reconnectAttempt = 0
        // The standby was already buffered and ready, so this connection counts as live: a dip
        // right after the swap is a real stall, not a slow first connect.
        hasPlayedSinceConnect = true
    }

    private func discardStandby() {
        standbyStatusObserver = nil
        standbyTimeoutTask?.cancel()
        standbyTimeoutTask = nil
        standbyPlayer?.replaceCurrentItem(with: nil)
        standbyPlayer = nil
        standbyItem = nil
        standbyProxy?.stop()
        standbyProxy = nil
    }

    /// Begins routing decoded stream PCM to `streamSink` for ShazamKit. Call only while
    /// identifying — a permanently-attached MTAudioProcessingTap on a live stream stalls the
    /// audio render once the app is backgrounded in CarPlay (radio cuts out after a few seconds
    /// and the Now Playing baton passes to Apple Music). The item is already playing by the time
    /// the user identifies, so its audio tracks are ready.
    func beginStreamTap() { activateStreamTap() }

    /// Detaches the passive tap when identification finishes, restoring untapped playback.
    func endStreamTap() {
        streamTap.remove()
        streamSink.set(nil)
        streamTapActive = false
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
            currentAppleMusicURL = nil
            updateNowPlayingInfo()
            if let track = currentTrack {
                resolveArtwork(track: track, artist: currentArtist, shazamURL: nil)
            }
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
        // Third line on CarPlay / lock screen: without this the station name disappears as
        // soon as a song supplies both title and artist.
        info[MPMediaItemPropertyAlbumTitle] = currentStation?.name ?? ""
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
    func updateNowPlayingFromShazam(title: String, artist: String?, artworkURL: URL?, appleMusicURL: URL?) {
        currentTrack = title
        currentArtist = artist
        trackIsFromShazam = true
        currentAppleMusicURL = appleMusicURL
        updateNowPlayingInfo()
        resolveArtwork(track: title, artist: artist, shazamURL: artworkURL)
    }

    /// Single entry point for cover art, whatever the title's source. ShazamKit hands us an
    /// artwork URL directly; stations that only broadcast an ICY title carry no image, so we
    /// look one up by artist + title through the iTunes Search API (free, keyless). Keyed so
    /// repeated identical metadata frames don't re-fetch, and token-guarded so a song change
    /// in a continuous stream never leaves the previous track's cover on screen.
    private func resolveArtwork(track: String, artist: String?, shazamURL: URL?) {
        let key = "\(artist ?? "")|\(track)".lowercased()
        // Shazam is authoritative and already holds the URL, so it may refresh even the same
        // key; metadata lookups dedup to avoid hammering the network on repeated ICY frames.
        if shazamURL == nil, key == lastArtworkKey { return }
        lastArtworkKey = key
        artworkResolveToken += 1
        let token = artworkResolveToken

        if let shazamURL {
            applyCover(shazamURL, seedTrack: track)
            return
        }

        // Metadata-only title: drop the old cover right away so the hero falls back to the
        // station logo, then resolve the new cover by artist + title.
        currentArtworkURL = nil
        setLockScreenToStationLogo(seedTrack: track)
        Task.detached(priority: .utility) { [weak self] in
            let found = await Self.lookupCoverArt(track: track, artist: artist)
            await MainActor.run {
                guard let self, token == self.artworkResolveToken, let found else { return }
                self.applyCover(found.artwork, seedTrack: track)
                self.currentAppleMusicURL = found.appleMusic
            }
        }
    }

    private func applyCover(_ url: URL, seedTrack: String) {
        currentArtworkURL = url
        loadArtwork(preferredURL: url.absoluteString,
                    initials: currentStation?.initials ?? "♪",
                    seed: currentStation?.name ?? seedTrack)
        // Keep the cover with the track in history, so the list still shows it later.
        if let station = currentStation {
            HistoryStore.shared.attachArtwork(url: url.absoluteString,
                                              appleMusicURL: currentAppleMusicURL?.absoluteString,
                                              title: seedTrack,
                                              stationName: station.name)
        }
    }

    private func setLockScreenToStationLogo(seedTrack: String) {
        loadArtwork(preferredURL: currentStation?.logoURL,
                    initials: currentStation?.initials ?? "♪",
                    seed: currentStation?.name ?? seedTrack)
    }

    /// Looks up cover art + Apple Music link for a metadata-only title via the iTunes Search
    /// API. Returns nil on any miss so the caller keeps the station logo.
    private nonisolated static func lookupCoverArt(track: String, artist: String?) async -> (artwork: URL, appleMusic: URL?)? {
        let term = [artist, track].compactMap { $0 }.joined(separator: " ")
        guard !term.isEmpty, var comps = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONDecoder().decode(ITunesSearchResponse.self, from: data),
              let hit = root.results.first,
              let art = hit.artworkUrl100 else { return nil }
        // artworkUrl100 ends in ".../100x100bb.jpg"; ask for 600 for a crisp hero image.
        let big = art.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        guard let artworkURL = URL(string: big) else { return nil }
        return (artworkURL, hit.trackViewUrl.flatMap { URL(string: $0) })
    }

    private struct ITunesSearchResponse: Decodable {
        let results: [Item]
        struct Item: Decodable {
            let artworkUrl100: String?
            let trackViewUrl: String?
        }
    }

    /// Called when the user re-runs identification. Drops a previous Shazam-derived title and
    /// artwork so the screen doesn't keep showing the last song while we listen for the new
    /// one. Real station metadata is left untouched.
    func prepareForReidentify() {
        guard trackIsFromShazam else { return }
        currentTrack = nil
        currentArtist = nil
        currentArtworkURL = nil
        currentAppleMusicURL = nil
        lastArtworkKey = nil
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
