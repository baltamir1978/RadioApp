import ShazamKit
import AVFoundation
import Combine

/// Identifies the currently playing song via ShazamKit (microphone).
/// Requires NSMicrophoneUsageDescription in Info.plist.
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
    @Published var isAvailable = false

    private var session: SHSession?
    private let audioEngine = AVAudioEngine()
    private var signatureGenerator = SHSignatureGenerator()

    override init() {
        super.init()
        isAvailable = true
    }

    // MARK: - Public API

    func identify() {
        guard case .idle = state else { return }
        requestMicrophoneAccess {
            self.startListening()
        }
    }

    func cancel() {
        stopListening()
        state = .idle
    }

    // MARK: - Private

    private func requestMicrophoneAccess(then action: @escaping () -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted { action() }
                else { self.state = .error("Permiso de micrófono denegado") }
            }
        }
    }

    private func startListening() {
        session = SHSession()
        session?.delegate = self
        signatureGenerator = SHSignatureGenerator()
        state = .listening

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                try self.signatureGenerator.append(buffer, at: nil)
            } catch {
                // Buffer append errors are non-fatal; ignore
            }
        }

        do {
            try audioEngine.start()
        } catch {
            state = .error("Error al iniciar el motor de audio")
            return
        }

        // After 5 seconds, send the accumulated signature for matching
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.matchSignature()
        }
    }

    private func matchSignature() {
        stopListening()
        guard let sig = try? signatureGenerator.signature() else {
            state = .noMatch
            return
        }
        session?.match(sig)
    }

    private func stopListening() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }
}

// MARK: - SHSessionDelegate

extension ShazamService: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        DispatchQueue.main.async {
            if let item = match.mediaItems.first {
                self.state = .found(item)
            } else {
                self.state = .noMatch
            }
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {
        DispatchQueue.main.async {
            self.state = .noMatch
        }
    }
}
