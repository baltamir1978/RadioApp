import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Task { @MainActor in showStationList() }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.interfaceController = nil
    }

    @MainActor
    private func showStationList() {
        let bridge = CarPlayBridge.shared
        let items: [CPListItem] = bridge.store.stations.map { station in
            let item = CPListItem(text: station.name, detailText: [station.genre, station.country].compactMap { $0 }.joined(separator: " · "))
            item.handler = { _, completion in
                Task { @MainActor in
                    bridge.player.play(station)
                    completion()
                }
            }
            return item
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: NSLocalizedString("my_stations", comment: ""), sections: [section])
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
    }
}
