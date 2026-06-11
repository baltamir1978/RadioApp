import CarPlay
import Combine
import UIKit

/// Drives the small CarPlay Dashboard pane that appears next to a navigation app in split
/// screen. The system fixes the pane's size — we can't enlarge it — but it allows up to two
/// shortcut buttons. We surface Play/Pause and Shazam so the user keeps song identification
/// without leaving the maps view.
class CarPlayDashboardSceneDelegate: UIResponder, CPTemplateApplicationDashboardSceneDelegate {
    private var dashboardController: CPDashboardController?
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationDashboardScene(
        _ scene: CPTemplateApplicationDashboardScene,
        didConnect dashboardController: CPDashboardController,
        to window: UIWindow
    ) {
        self.dashboardController = dashboardController
        Task { @MainActor in
            observeState()
            updateButtons()
        }
    }

    func templateApplicationDashboardScene(
        _ scene: CPTemplateApplicationDashboardScene,
        didDisconnect dashboardController: CPDashboardController,
        from window: UIWindow
    ) {
        self.dashboardController = nil
        cancellables.removeAll()
    }

    @MainActor
    private func updateButtons() {
        let bridge = CarPlayBridge.shared
        let player = bridge.player

        let playPause = CPDashboardButton(
            titleVariants: [player.isPlaying
                            ? NSLocalizedString("pause", comment: "")
                            : NSLocalizedString("play", comment: "")],
            subtitleVariants: [player.currentStation?.name ?? ""],
            image: symbol(player.isPlaying ? "pause.fill" : "play.fill")
        ) { _ in
            Task { @MainActor in player.togglePlayPause() }
        }

        let shazam = CPDashboardButton(
            titleVariants: [NSLocalizedString("identify_song", comment: "")],
            subtitleVariants: [player.currentTrack ?? ""],
            image: symbol(bridge.shazam.isListening ? "waveform.circle.fill" : "waveform.and.magnifyingglass")
        ) { _ in
            Task { @MainActor in bridge.shazam.identify() }
        }

        dashboardController?.shortcutButtons = [playPause, shazam]
    }

    @MainActor
    private func observeState() {
        let bridge = CarPlayBridge.shared
        Publishers.MergeMany(
            bridge.player.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            bridge.player.$currentStation.map { _ in () }.eraseToAnyPublisher(),
            bridge.player.$currentTrack.map { _ in () }.eraseToAnyPublisher(),
            bridge.shazam.$isListening.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.updateButtons() }
        .store(in: &cancellables)
    }

    private func symbol(_ name: String) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        return UIImage(systemName: name, withConfiguration: config) ?? UIImage()
    }
}
