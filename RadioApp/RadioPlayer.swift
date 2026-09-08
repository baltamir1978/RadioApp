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
    private var routeChangeTask: Task<Void, Never>?
    /// Whether the last known output route left the phone (car, headphones, AirPlay).
    private var wasOnExternalRoute = false
    /// Recovers a player that went to `.paused` on its own while the user still wants audio.
    private var pauseRecoveryTask: Task<Void, Never>?
    private var pauseRecoveryGeneration = 0
    private let streamTap = AudioStreamTap()
    /// Receives decoded PCM from the live stream while a tap is active (for ShazamKit).
    let streamSink = StreamSinkBox()
    private var streamTapActive = false
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var artworkToken = 0
    /// "artist|title" of the last resolved cover, so repeated ICY frames for the same song
    /// don't re-hit the network. Bumped independently of `artworkToken` (image-load race).
    private var lastArtworkKey: String?
    /// Covers already resolved this session, keyed by "artist|title". A nil value records a
    /// song iTunes has no cover for, so we don't ask again every time it plays.
    private var artworkCache: [String: ResolvedArtwork?] = [:]
    /// Songs whose lookup (including retries) is still running, so repeated ICY frames for the
    /// same track don't start a second one.
    private var artworkLookupsInFlight: Set<String> = []
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
    /// Identifies the watchdog currently owning `watchdogTask`, so a cancelled one can't clear
    /// a newer timer out of the slot on its way out.
    private var watchdogGeneration = 0
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
        setupRouteChangeHandling()
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
        // The user chose to play right now, so whatever they're on is the route they meant —
        // including the phone's own speaker.
        wasOnExternalRoute = Self.isOutputExternal()

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
            wasOnExternalRoute = Self.isOutputExternal()
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
            // A pause the user didn't ask for. AVPlayer parks here after an interruption it
            // never reports as ended, after a route change, or when a live item quietly gives
            // up — and nothing else in this class was watching for it, so the app sat there
            // showing "playing" with no sound until the user pressed play twice.
            if intendsToPlay { scheduleUnexpectedPauseRecovery() }
        @unknown default:
            break
        }
    }

    /// Nudges a self-paused player back to life: resume first, rebuild the stream if that
    /// doesn't take. Deliberately delayed — `replaceCurrentItem` during a standby promotion
    /// passes through `.paused` for an instant, and that is not a fault.
    private func scheduleUnexpectedPauseRecovery() {
        guard pauseRecoveryTask == nil else { return }
        pauseRecoveryGeneration += 1
        let generation = pauseRecoveryGeneration
        pauseRecoveryTask = Task { @MainActor [weak self] in
            // Spread out rather than one shot: an interruption can outlast any single delay,
            // and giving up after the first try is what left the app silent until the user
            // pressed play twice.
            for wait in [1, 5, 15, 30, 60, 120] as [UInt64] {
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                guard let self, !Task.isCancelled, self.intendsToPlay else { break }
                guard self.player?.timeControlStatus == .paused else { break }
                // Never resume into the phone's own speaker after the car stereo dropped out.
                guard !self.fellBackToBuiltInSpeaker() else {
                    playbackLog.notice("paused with output back on the built-in speaker — staying quiet")
                    self.intendsToPlay = false
                    self.isPlaying = false
                    self.updateNowPlayingInfo()
                    break
                }
                // Some interruptions (a call answered on the car's screen) never send `.ended`,
                // so waiting for the notification means waiting forever. Claiming the session
                // is the honest test: it only succeeds once nobody else holds the audio.
                do { try AVAudioSession.sharedInstance().setActive(true) } catch { continue }
                playbackLog.notice("player paused itself — resuming")
                self.player?.play()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, self.intendsToPlay,
                      self.player?.timeControlStatus != .playing else { break }
                playbackLog.notice("resume didn't take — rebuilding the stream")
                self.scheduleReconnect()
                break
            }
            // Same trap as the watchdog: a cancelled task resumes a hop later, so only clear
            // the slot if it still holds this attempt.
            guard let self, self.pauseRecoveryGeneration == generation else { return }
            self.pauseRecoveryTask = nil
        }
    }

    /// One-shot timer: if the stream still isn't playing after the applicable grace, reconnect.
    /// Idempotent — repeated stall signals won't pile up timers.
    private func armWatchdog() {
        guard intendsToPlay, watchdogTask == nil else { return }
        // A connection that has never played is still buffering, not stalled — give it room.
        let grace = hasPlayedSinceConnect ? stallGrace : connectGrace
        watchdogGeneration += 1
        let generation = watchdogGeneration
        watchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
            // Only clear the slot if it still holds *this* timer: a cancelled task resumes one
            // hop later, and blindly nil-ing the slot there orphaned a watchdog that had been
            // armed in between — it stayed alive, uncancellable, and fired a spurious rebuild.
            if self.watchdogGeneration == generation { self.watchdogTask = nil }
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
            // The car stereo going away is not a broken stream; rebuilding here is what used
            // to move the sound to the phone's speaker mid-drive.
            guard !self.fellBackToBuiltInSpeaker() else {
                playbackLog.notice("skipping reconnect — output fell back to the built-in speaker")
                self.intendsToPlay = false
                self.isReconnecting = false
                self.isPlaying = false
                self.updateNowPlayingInfo()
                return
            }
            playbackLog.notice("rebuilding connection (attempt \(self.reconnectAttempt, privacy: .public))")
            self.teardownStream()
            self.startStream()
        }
    }

    private func cancelReconnect() {
        disarmWatchdog()
        cancelPreflight()
        pauseRecoveryTask?.cancel()
        pauseRecoveryTask = nil
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
            let track: String
            let artist: String?
            if parts.count == 2 {
                artist = parts[0]
                track = parts[1]
            } else {
                track = cleaned
                artist = nil
            }
            // A station announcing itself is not a song — don't let it reach the screen.
            guard !Self.announcesStation(track: track, artist: artist,
                                         station: currentStation?.name ?? "") else {
                clearStreamMetadata()
                return
            }
            currentArtist = artist
            currentTrack = track
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

    /// Whether a StreamTitle is the station identifying itself rather than naming a song.
    /// Stations broadcast their own name or a slogan when nothing is on air — Cadena 100
    /// sends "La Mejor Variedad Musical - CADENA 100" permanently and never publishes the
    /// actual track. Split on the dash that reads exactly like artist + title, so it reached
    /// the screen as a song, put a bogus track on the lock screen, and made CarPlay offer the
    /// heart button instead of Shazam. Either side matching the station's name gives it away.
    private static func announcesStation(track: String, artist: String?, station: String) -> Bool {
        let stationKey = compact(station)
        guard !stationKey.isEmpty else { return false }
        return [track, artist].compactMap { $0 }.contains { compact($0) == stationKey }
    }

    /// Case-, accent- and separator-insensitive form, so "CADENA 100" matches "Cadena 100".
    private static func compact(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
         .components(separatedBy: CharacterSet.alphanumerics.inverted)
         .joined()
    }

    /// Drops a title that came from stream metadata, returning the screen (and CarPlay's
    /// button) to the station. A Shazam result outranks stream metadata, so it survives.
    private func clearStreamMetadata() {
        guard !trackIsFromShazam, currentTrack != nil else { return }
        currentTrack = nil
        currentArtist = nil
        currentArtworkURL = nil
        currentAppleMusicURL = nil
        lastArtworkKey = nil
        updateNowPlayingInfo()
        setLockScreenToStationLogo(seedTrack: currentStation?.name ?? "")
    }

    private func setupAudioSession() {
        do {
            // `.allowBluetoothHFP` asks for the hands-free profile: mono, telephone-grade, and
            // on some car kits the system picks it over A2DP/CarPlay for a playback-only
            // session, then drops back to the phone speaker when the call-audio link is
            // released. A pure playback session already reaches A2DP and CarPlay.
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        wasOnExternalRoute = Self.isOutputExternal()
    }

    // MARK: - Output route

    /// Whether audio is currently leaving the phone for a car, headphones or AirPlay, rather
    /// than the built-in speaker.
    private nonisolated static func isOutputExternal() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            output.portType != .builtInSpeaker && output.portType != .builtInReceiver
        }
    }

    /// Follows route changes so a car stereo dropping out never turns into the radio blaring
    /// from the phone's own speaker.
    ///
    /// When Bluetooth or CarPlay goes away iOS moves the route to the built-in speaker and
    /// pauses the player. Our reconnect logic used to read that pause as a dead stream, rebuild
    /// it and call `play()` again — which is exactly how a quiet drive turned into the phone
    /// suddenly playing out loud. Losing the output device is a reason to stop, not to retry,
    /// so we clear the intent to play along with any pending reconnect.
    private func setupRouteChangeHandling() {
        routeChangeTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                guard let self else { return }
                let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                let reason = raw.flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) } ?? .unknown
                self.handleRouteChange(reason)
            }
        }
    }

    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        // Only ever set on the way *out*: forgetting we had been on the car stereo the moment
        // iOS drops us onto the speaker would defeat `fellBackToBuiltInSpeaker`. Starting
        // playback deliberately is what clears it (see `play`).
        if Self.isOutputExternal() { wasOnExternalRoute = true }
        guard reason == .oldDeviceUnavailable else { return }
        playbackLog.notice("output device went away — pausing instead of falling back to the speaker")
        guard intendsToPlay else { return }
        intendsToPlay = false
        cancelReconnect()
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    /// True when playback would now come out of the phone's own speaker after having been on a
    /// car stereo / headphones. Nothing automatic — a watchdog, a reconnect, a resumed
    /// interruption — may start audio in that state.
    private func fellBackToBuiltInSpeaker() -> Bool {
        wasOnExternalRoute && !Self.isOutputExternal()
    }

    private func setupInterruptionHandling() {
        interruptionTask = Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { continue }
                switch type {
                case .began:
                    wasPlayingBeforeInterruption = isPlaying || intendsToPlay
                    isPlaying = false
                    updateNowPlayingInfo()
                case .ended:
                    guard wasPlayingBeforeInterruption, player != nil else { continue }
                    // Only resume when the system says the interruption is over *and* wants us
                    // back. Some interruptions (a call the user takes over CarPlay) end without
                    // `shouldResume`, and forcing playback there steals the audio session back.
                    let options = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt)
                        .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
                    guard options.contains(.shouldResume), !fellBackToBuiltInSpeaker() else {
                        intendsToPlay = false
                        updateNowPlayingInfo()
                        continue
                    }
                    try? AVAudioSession.sharedInstance().setActive(true)
                    intendsToPlay = true
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
        let station = currentStation?.name ?? ""
        let track = (currentTrack ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = (currentArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Title / artist / album are stacked as three lines on the lock screen and CarPlay.
        // Each one is only filled when it says something the lines above don't: falling back
        // to the station name for every empty field printed it three times over between songs.
        // A stream whose StreamTitle is just the station's own name counts as "no song".
        let hasSong = !track.isEmpty && track.caseInsensitiveCompare(station) != .orderedSame
        info[MPMediaItemPropertyTitle] = hasSong ? track : station
        if hasSong, !artist.isEmpty, artist.caseInsensitiveCompare(station) != .orderedSame {
            info[MPMediaItemPropertyArtist] = artist
        }
        // Third line: without it the station name disappears as soon as a song takes over
        // the first two — but when the title already *is* the station, repeating it is noise.
        if hasSong, !station.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = station
        }
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

        if let shazamURL {
            applyCover(shazamURL, seedTrack: track)
            return
        }

        // Metadata-only title: drop the old cover right away so the hero falls back to the
        // station logo, then resolve the new cover by artist + title.
        currentArtworkURL = nil
        setLockScreenToStationLogo(seedTrack: track)

        // Already looked this song up — reuse it. The cache is what keeps the cover on screen
        // across a reconnect, which re-delivers the same ICY title on a brand-new metadata
        // output, and across the station's own ident frames coming and going between songs.
        if let cached = artworkCache[key] {
            if let cached { applyResolved(cached, seedTrack: track) }
            return
        }
        guard !artworkLookupsInFlight.contains(key) else { return }
        artworkLookupsInFlight.insert(key)
        startArtworkLookup(key: key, track: track, artist: artist)
    }

    /// Resolves a cover through the iTunes Search API, retrying a few times when the *network*
    /// fails rather than when the song is genuinely unknown.
    ///
    /// A single lost request used to cost the whole song its artwork: the key was marked as
    /// looked-up before the answer came back, so every later ICY frame for the same track was
    /// deduped away and the hero kept showing the station logo until the song changed. On a
    /// mobile connection in a car that miss is routine, not rare.
    private func startArtworkLookup(key: String, track: String, artist: String?) {
        Task { @MainActor [weak self] in
            let backoff: [UInt64] = [2, 5, 12]
            for attempt in 0...backoff.count {
                let outcome = await Self.lookupCoverArt(track: track, artist: artist)
                guard let self else { return }
                switch outcome {
                case .found(let artwork, let appleMusic):
                    let resolved = ResolvedArtwork(artwork: artwork, appleMusic: appleMusic)
                    self.rememberArtwork(resolved, for: key)
                    self.artworkLookupsInFlight.remove(key)
                    // Only paint it if this is still the song on air; the cache keeps it for
                    // when the same track comes round again.
                    if key == self.lastArtworkKey { self.applyResolved(resolved, seedTrack: track) }
                    return
                case .notFound:
                    playbackLog.notice("no cover found for \(track, privacy: .public)")
                    self.rememberArtwork(nil, for: key)
                    self.artworkLookupsInFlight.remove(key)
                    return
                case .failed:
                    guard attempt < backoff.count, key == self.lastArtworkKey else {
                        self.artworkLookupsInFlight.remove(key)
                        return
                    }
                    playbackLog.notice("cover lookup failed for \(track, privacy: .public) — retrying")
                    try? await Task.sleep(nanoseconds: backoff[attempt] * 1_000_000_000)
                }
            }
            self?.artworkLookupsInFlight.remove(key)
        }
    }

    private func applyResolved(_ resolved: ResolvedArtwork, seedTrack: String) {
        applyCover(resolved.artwork, seedTrack: seedTrack)
        currentAppleMusicURL = resolved.appleMusic
    }

    /// Keeps the lookup cache small — a long drive is a lot of songs, and only the recent ones
    /// can still come back around.
    private func rememberArtwork(_ resolved: ResolvedArtwork?, for key: String) {
        if artworkCache.count >= 60 { artworkCache.removeAll() }
        artworkCache[key] = .some(resolved)
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
    private nonisolated static func lookupCoverArt(track: String, artist: String?) async -> ArtworkLookup {
        let term = [artist, track].compactMap { $0 }.joined(separator: " ")
        guard !term.isEmpty, var comps = URLComponents(string: "https://itunes.apple.com/search") else { return .notFound }
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = comps.url else { return .notFound }
        var request = URLRequest(url: url)
        // Well short of the default 60s: a cover that arrives a minute late is no use on a
        // station that has already moved on, and a shorter wait is what makes retrying viable.
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return .failed }
        // iTunes Search throttles bursts with a 403; that is a transient failure, not a miss.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            playbackLog.error("iTunes search returned \(http.statusCode, privacy: .public)")
            return .failed
        }
        guard let root = try? JSONDecoder().decode(ITunesSearchResponse.self, from: data) else { return .failed }
        guard let hit = root.results.first, let art = hit.artworkUrl100 else { return .notFound }
        // artworkUrl100 ends in ".../100x100bb.jpg"; ask for 600 for a crisp hero image.
        let big = art.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        guard let artworkURL = URL(string: big) else { return .notFound }
        return .found(artworkURL, hit.trackViewUrl.flatMap { URL(string: $0) })
    }

    /// Why a cover lookup ended, so the caller can tell "this song has no cover" (final) from
    /// "the network let us down" (worth retrying).
    private enum ArtworkLookup {
        case found(URL, URL?)
        case notFound
        case failed
    }

    private struct ResolvedArtwork {
        let artwork: URL
        let appleMusic: URL?
    }

    // Decoded off the main actor inside `lookupCoverArt`, so the conformance must not inherit
    // the type-wide @MainActor isolation this project infers.
    private nonisolated struct ITunesSearchResponse: Decodable {
        let results: [Item]
        nonisolated struct Item: Decodable {
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
