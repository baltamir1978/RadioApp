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
final class StreamMatcher: @unchecked Sendable {
    let session: SHSession

    init(delegate: SHSessionDelegate) {
        session = SHSession()
        session.delegate = delegate
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        session.matchStreamingBuffer(buffer, at: nil)
    }
}

/// Identifies the song currently playing.
///
/// Primary path: a passive tap on the radio stream (no microphone, works with
/// headphones / AirPlay). The tap is kept active by `RadioPlayer` while a station
/// plays, so identification just attaches a `StreamMatcher` to `RadioPlayer.streamSink`.
/// Fallback: the microphone, only when nothing is streaming.
@MainActor
class ShazamService: NSObject, ObservableObject, SHSessionDelegate {
    @Published var isListening = false
    @Published var match: ShazamMatch?
    @Published var errorMessage: String?

    private let listenWindow: TimeInterval = 12

    private var matcher: StreamMatcher?
    private var micSession: SHSession?
    private var audioEngine: AVAudioEngine?
    private var identifyTimer: Timer?
    private var usingStreamTap = false

    func identify() {
        if isListening { stop(); return }
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
            RadioPlayer.shared.streamSink.set(nil)
            usingStreamTap = false
        }
        matcher = nil

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
        RadioPlayer.shared.streamSink.set { matcher.append($0) }
        scheduleTimeout()
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
        }
    }

    // A single unmatched signature is normal while streaming — the timeout decides.
    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {}
}
