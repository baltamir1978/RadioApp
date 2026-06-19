import Foundation
import Combine
import ShazamKit
import AVFoundation

struct ShazamMatch {
    let title: String
    let artist: String
    let artworkURL: URL?
    let appleMusicURL: URL?
}

/// Feeds the live stream's decoded PCM straight to a ShazamKit session.
/// Lives off the main actor because `append` is called from the audio render thread.
/// We pass the buffers through untouched — ShazamKit handles resampling internally,
/// and any per-buffer format conversion here would introduce discontinuities that
/// ruin the fingerprint.
nonisolated final class StreamMatcher: @unchecked Sendable {
    let session: SHSession
    private let lock = NSLock()
    private var _bufferCount = 0

    /// Number of PCM buffers fed so far. Read on the main actor to tell whether the passive
    /// tap actually delivered audio for this stream (some stations' delivery defeats the tap).
    var bufferCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _bufferCount
    }

    init(delegate: SHSessionDelegate) {
        session = SHSession()
        session.delegate = delegate
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); _bufferCount += 1; lock.unlock()
        session.matchStreamingBuffer(buffer, at: nil)
    }
}

/// Identifies the song currently playing.
///
/// Primary path: a passive tap on the radio stream (no microphone, works with
/// headphones / AirPlay). The tap is kept active by `RadioPlayer` while a station
/// plays, so identification just attaches a `StreamMatcher` to `RadioPlayer.streamSink`.
///
/// Second path (`StreamDecoder`): when the passive tap is starved because a station's delivery
/// defeats it (ad-handler redirect chains, tokenized / HLS endpoints, e.g. Kiss FM), we open
/// our own connection to the stream, decode it ourselves, and feed that to ShazamKit. This is
/// route-independent, so it recognizes the song in the car (CarPlay), over AirPlay and on
/// headphones — anywhere the microphone has no acoustic path.
///
/// Fallback: the microphone, used when nothing is streaming (identify ambient audio).
@MainActor
class ShazamService: NSObject, ObservableObject, SHSessionDelegate {
    @Published var isListening = false
    @Published var match: ShazamMatch?
    @Published var errorMessage: String?

    private let listenWindow: TimeInterval = 12
    /// How long a recognized song stays on screen before we clear it back to the station.
    private let resultDisplayWindow: TimeInterval = 60
    /// Below this many tapped buffers over a full listen window, the passive stream tap is
    /// considered to have failed to capture audio (vs. a genuine "song not found").
    private static let minTapBuffers = 10

    private var matcher: StreamMatcher?
    private var micSession: SHSession?
    private var audioEngine: AVAudioEngine?
    private var identifyTimer: Timer?
    private var displayTimer: Timer?
    private var usingStreamTap = false
    private var remoteDecoder: StreamDecoder?
    private var remoteMatcher: StreamMatcher?
    private var usingRemoteDecoder = false

    func identify() {
        if isListening { stop(); return }
        displayTimer?.invalidate()
        match = nil
        errorMessage = nil
        isListening = true

        if RadioPlayer.shared.isPlaying {
            startStreamTapMode()
        } else {
            startMicMode()
        }
    }

    func stop() {
        identifyTimer?.invalidate()
        identifyTimer = nil

        if usingStreamTap {
            RadioPlayer.shared.endStreamTap()
            usingStreamTap = false
        }
        matcher = nil

        if usingRemoteDecoder {
            remoteDecoder?.stop()
            remoteDecoder = nil
            remoteMatcher = nil
            usingRemoteDecoder = false
        }

        if audioEngine != nil {
            stopEngine()
            restoreAudioSession()
        }
        micSession = nil

        isListening = false
    }

    // MARK: - Stream-tap path

    private func startStreamTapMode() {
        let matcher = StreamMatcher(delegate: self)
        self.matcher = matcher
        usingStreamTap = true
        RadioPlayer.shared.beginStreamTap()
        RadioPlayer.shared.streamSink.set { matcher.append($0) }
        identifyTimer = Timer.scheduledTimer(withTimeInterval: listenWindow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.streamTapTimedOut() }
        }
    }

    /// The stream tap produced no match within the window. Two causes:
    /// - the tap received audio but ShazamKit found nothing → a genuine no-match.
    /// - the tap was starved (the station's delivery defeats it) → recognize via our own
    ///   decoded connection, which works on any output route (car / AirPlay / headphones).
    private func streamTapTimedOut() {
        guard isListening, usingStreamTap else { return }
        let delivered = matcher?.bufferCount ?? 0
        RadioPlayer.shared.endStreamTap()
        usingStreamTap = false
        matcher = nil

        if delivered < Self.minTapBuffers {
            startRemoteDecoderMode()
        } else {
            errorMessage = NSLocalizedString("no_match_found", comment: "")
            stop()
        }
    }

    // MARK: - Remote-decoder path (route-independent)

    private func startRemoteDecoderMode() {
        guard let urlString = RadioPlayer.shared.currentStation?.streamURL,
              let url = URL(string: urlString) else {
            errorMessage = NSLocalizedString("no_match_found", comment: "")
            stop()
            return
        }
        let matcher = StreamMatcher(delegate: self)
        remoteMatcher = matcher
        let decoder = StreamDecoder(url: url) { matcher.append($0) }
        remoteDecoder = decoder
        usingRemoteDecoder = true
        decoder.start()
        // A fresh, slightly longer window — the second connection has to buffer up first.
        identifyTimer = Timer.scheduledTimer(withTimeInterval: listenWindow + 4, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                self.errorMessage = NSLocalizedString("no_match_found", comment: "")
                self.stop()
            }
        }
    }

    private func scheduleTimeout() {
        identifyTimer = Timer.scheduledTimer(withTimeInterval: listenWindow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                self.errorMessage = NSLocalizedString("no_match_found", comment: "")
                self.stop()
            }
        }
    }

    // MARK: - Microphone fallback

    private func startMicMode() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = await AVAudioApplication.requestRecordPermission()
            } else {
                granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
                }
            }
            guard granted else {
                self.errorMessage = NSLocalizedString("mic_denied", comment: "")
                self.isListening = false
                return
            }
            self.startEngine()
        }
    }

    private func startEngine() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.mixWithOthers, .allowBluetoothHFP, .allowAirPlay]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let session = SHSession()
            session.delegate = self
            micSession = session

            let engine = AVAudioEngine()
            audioEngine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak session] buffer, time in
                session?.matchStreamingBuffer(buffer, at: time)
            }

            try engine.start()
            scheduleTimeout()
        } catch {
            errorMessage = error.localizedDescription
            stopEngine()
            restoreAudioSession()
            isListening = false
        }
    }

    private func stopEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func restoreAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default,
            options: [.allowAirPlay, .allowBluetoothHFP]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - SHSessionDelegate

    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        let result = ShazamMatch(
            title: item.title ?? "",
            artist: item.artist ?? "",
            artworkURL: item.artworkURL,
            appleMusicURL: item.appleMusicURL
        )
        Task { @MainActor in
            guard self.isListening else { return }
            self.match = result
            self.stop()
            self.scheduleResultClear()
        }
    }

    /// Auto-clears a recognized song after `resultDisplayWindow` so a stale title/artwork
    /// doesn't linger once the track has likely changed. Re-running identify cancels it.
    private func scheduleResultClear() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: resultDisplayWindow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.match = nil
                RadioPlayer.shared.prepareForReidentify()
            }
        }
    }

    // A single unmatched signature is normal while streaming — the timeout decides.
    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {}
}
