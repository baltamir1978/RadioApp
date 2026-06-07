import ShazamKit
import AVFoundation
import Combine

/// Identifies the currently playing song via ShazamKit.
///
/// Primary path: taps the decoded audio of the live stream (`RadioPlayer.installStreamTap`)
/// and feeds it to `SHSession.matchStreamingBuffer`. This works with headphones / AirPlay
/// and needs no microphone permission.
///
/// Fallback path (only when nothing is streaming): the microphone.
/// Requires `NSMicrophoneUsageDescription` in Info.plist.
@MainActor
final class ShazamService: NSObject, ObservableObject {
    enum State {
        case idle
        case listening
        case found(SHMatchedMediaItem)
        case noMatch
        case error(String)
    }

    @Published var state: State = .idle
    @Published var isAvailable = true

    /// Seconds to listen before giving up.
    private let timeout: TimeInterval = 12

    private var session: SHSession?
    private var audioEngine: AVAudioEngine?
    private var usingStreamTap = false
    private var timeoutTask: Task<Void, Never>?
    private weak var player: RadioPlayer?

    // MARK: - Public API

    /// Starts identification. Prefers the live stream of `player`; falls back to the mic.
    func identify(using player: RadioPlayer) {
        if case .listening = state { return }   // already running
        stopInternal()                          // clean any previous attempt
        self.player = player

        let newSession = SHSession()
        newSession.delegate = self
        session = newSession

        // Capture the session locally so the realtime audio thread never touches `self`.
        let installed = player.installStreamTap { [weak newSession] buffer, time in
            newSession?.matchStreamingBuffer(buffer, at: time)
        }

        if installed {
            usingStreamTap = true
            state = .listening
            scheduleTimeout()
        } else {
            // No stream available (e.g. nothing playing) → use the microphone.
            startMicMode()
        }
    }

    func cancel() {
        stopInternal()
        state = .idle
    }

    // MARK: - Lifecycle

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.timeout ?? 12) * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if case .listening = self.state {
                self.stopInternal()
                self.state = .noMatch
            }
        }
    }

    /// Tears down audio capture without changing `state`.
    private func stopInternal() {
        timeoutTask?.cancel()
        timeoutTask = nil

        if usingStreamTap {
            player?.removeStreamTap()
            usingStreamTap = false
        } else if audioEngine != nil {
            stopEngine()
            restoreAudioSession()
        }

        session = nil
    }

    // MARK: - Microphone fallback

    private func startMicMode() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if granted {
                    self.startEngine()
                } else {
                    self.session = nil
                    self.state = .error(String(localized: "shazam.micDenied"))
                }
            }
        }
    }

    private func startEngine() {
        do {
            // .mixWithOthers keeps any other audio alive; we restore .playback afterwards.
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.mixWithOthers, .allowBluetoothHFP, .allowAirPlay]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let engine = AVAudioEngine()
            audioEngine = engine
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak session] buffer, time in
                session?.matchStreamingBuffer(buffer, at: time)
            }

            try engine.start()
            usingStreamTap = false
            state = .listening
            scheduleTimeout()
        } catch {
            stopEngine()
            restoreAudioSession()
            state = .error(String(localized: "shazam.error"))
        }
    }

    private func stopEngine() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
    }

    /// Hands the audio session back to the radio player (.playback).
    private func restoreAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// MARK: - SHSessionDelegate

extension ShazamService: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard case .listening = self.state else { return }
            self.stopInternal()
            if let item = match.mediaItems.first {
                self.state = .found(item)
            } else {
                self.state = .noMatch
            }
        }
    }

    // A single unmatched signature is normal while streaming — let the timeout decide.
    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {}
}
