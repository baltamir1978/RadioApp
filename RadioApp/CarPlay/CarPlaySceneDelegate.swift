import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    // Shared singletons — CarPlay runs in a separate scene without the SwiftUI env,
    // but must drive the *same* player/store as the phone UI.
    private let player = RadioPlayer.shared
    private let store = StationsStore.shared

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(makeStationList(), animated: false, completion: nil)
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
        return CPListTemplate(title: String(localized: "tab.stations"), sections: [section])
    }

    private func showNowPlaying() {
        interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }
}
