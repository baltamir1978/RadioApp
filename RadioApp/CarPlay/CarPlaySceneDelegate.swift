import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    // Shared singletons — CarPlay runs in a separate scene without SwiftUI env
    private let player = CarPlayBridge.shared.player
    private let store = CarPlayBridge.shared.store

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(makeStationList(), animated: false, completion: nil)
        setupNowPlayingButton()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // MARK: - Templates

    private func makeStationList() -> CPListTemplate {
        let items = store.stations.map { station -> CPListItem in
            let item = CPListItem(text: station.name, detailText: nil)
            item.handler = { [weak self] _, completion in
                self?.player.play(station)
                self?.showNowPlaying()
                completion()
            }
            return item
        }
        let section = CPListSection(items: items)
        return CPListTemplate(title: "Emisoras", sections: [section])
    }

    private func setupNowPlayingButton() {
        let nowPlayingButton = CPNowPlayingTemplate.shared
        interfaceController?.setRootTemplate(makeStationList(), animated: false, completion: nil)
        _ = nowPlayingButton
    }

    private func showNowPlaying() {
        interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }
}

// MARK: - Bridge to share player/store between scenes

final class CarPlayBridge {
    static let shared = CarPlayBridge()
    let player = RadioPlayer()
    let store = StationsStore()
    private init() {}
}
