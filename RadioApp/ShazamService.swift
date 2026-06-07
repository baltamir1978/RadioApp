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

@MainActor
class ShazamService: NSObject, ObservableObject, SHSessionDelegate {
    @Published var isListening = false
    @Published var match: ShazamMatch?
    @Published var errorMessage: String?

    private var session: SHSession?
    private var audioEngine: AVAudioEngine?
    private var identifyTimer: Timer?
    private var usingStreamTap = false

    func identify() {
        if isListening { stop(); return }
        match = nil
        errorMessage = nil

        let shazamSession = SHSession()
        shazamSession.delegate = self
        session = shazamSession

        // Prefer tapping the player stream — works with headphones and avoids mic permission
        let installed = RadioPlayer.shared.installStreamTap { [weak self] buffer, time in
            self?.session?.matchStreamingBuffer(buffer, at: time)
        }

        if installed {
            usingStreamTap = true
            isListening = true
            scheduleTimeout()
        } else {
            // Fallback: mic (e.g. when no station is loaded)
            usingStreamTap = false
            startMicMode()
        }
    }

    func stop() {
        identifyTimer?.invalidate()
        identifyTimer = nil

        if usingStreamTap {
            RadioPlayer.shared.removeStreamTap()
            usingStreamTap = false
        } else {
            stopEngine()
            restoreAudioSession()
        }

        session = nil
        isListening = false
    }

    // MARK: - Stream tap path

    private func scheduleTimeout() {
        identifyTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                self.errorMessage = NSLocalizedString("no_match_found", comment: "")
                self.stop()
            }
        }
    }

    // MARK: - Mic fallback path

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
            if granted {
                self.startEngine()
            } else {
                self.session = nil
                self.errorMessage = "Permiso de micrófono denegado. Actívalo en Ajustes."
            }
        }
    }

    private func startEngine() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.mixWithOthers, .allowBluetoothHFP, .allowAirPlay]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let engine = AVAudioEngine()
            audioEngine = engine
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, time in
                self?.session?.matchStreamingBuffer(buffer, at: time)
            }

            try engine.start()
            isListening = true
            scheduleTimeout()

        } catch {
            errorMessage = error.localizedDescription
            stopEngine()
            restoreAudioSession()
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
            self.match = result
            self.stop()
        }
    }

    // One unmatched signature is normal — let the 12-second timer decide
    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {}
}
