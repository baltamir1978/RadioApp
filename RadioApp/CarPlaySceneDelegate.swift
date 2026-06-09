import CarPlay
import Combine
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Task { @MainActor in
            showStationList()
            observeState()
            updateNowPlayingButtons()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.interfaceController = nil
        cancellables.removeAll()
    }

    // MARK: - Station list

    @MainActor
    private func showStationList() {
        let bridge = CarPlayBridge.shared
        let items: [CPListItem] = bridge.store.stations.map { station in
            let item = CPListItem(text: station.name, detailText: [station.genre, station.country].compactMap { $0 }.joined(separator: " · "))
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    bridge.player.play(station)
                    self?.showNowPlaying()
                    completion()
                }
            }
            return item
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: NSLocalizedString("my_stations", comment: ""), sections: [section])
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
    }

    @MainActor
    private func showNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        guard interfaceController?.topTemplate !== nowPlaying else { return }
        interfaceController?.pushTemplate(nowPlaying, animated: true, completion: nil)
    }

    // MARK: - Now Playing buttons (favorite + Shazam)

    @MainActor
    private func updateNowPlayingButtons() {
        let bridge = CarPlayBridge.shared
        let player = bridge.player

        let button: CPNowPlayingImageButton
        if let track = player.currentTrack, !track.isEmpty {
            // The station already tells us the song — Shazam is pointless, so offer
            // the favorite (heart) action instead.
            let isFavorite = HistoryStore.shared.isFavorite(title: track,
                                                            stationName: player.currentStation?.name)
            button = CPNowPlayingImageButton(image: symbol(isFavorite ? "heart.fill" : "heart")) { [weak self] _ in
                Task { @MainActor in self?.toggleFavorite() }
            }
        } else {
            // No metadata — let the user identify what's playing with Shazam.
            let shazamSymbol = bridge.shazam.isListening ? "waveform.circle.fill" : "waveform.and.magnifyingglass"
            button = CPNowPlayingImageButton(image: symbol(shazamSymbol)) { _ in
                Task { @MainActor in bridge.shazam.identify() }
            }
        }

        CPNowPlayingTemplate.shared.updateNowPlayingButtons([button])
    }

    @MainActor
    private func toggleFavorite() {
        let player = CarPlayBridge.shared.player
        guard let station = player.currentStation,
              let track = player.currentTrack, !track.isEmpty else { return }
        HistoryStore.shared.toggleFavoriteForNowPlaying(title: track,
                                                        artist: player.currentArtist,
                                                        stationName: station.name)
        updateNowPlayingButtons()
    }

    private func symbol(_ name: String) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        return UIImage(systemName: name, withConfiguration: config) ?? UIImage()
    }

    // MARK: - State observation

    @MainActor
    private func observeState() {
        let bridge = CarPlayBridge.shared

        // Refresh the favorite glyph as the live track changes.
        bridge.player.$currentTrack
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateNowPlayingButtons() }
            .store(in: &cancellables)

        // Reflect the Shazam button's listening state.
        bridge.shazam.$isListening
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateNowPlayingButtons() }
            .store(in: &cancellables)

        // Persist + surface a Shazam match identified from CarPlay.
        bridge.shazam.$match
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] match in self?.handleShazamMatch(match) }
            .store(in: &cancellables)
    }

    @MainActor
    private func handleShazamMatch(_ match: ShazamMatch) {
        let player = CarPlayBridge.shared.player
        player.updateNowPlayingFromShazam(title: match.title, artist: match.artist, artworkURL: match.artworkURL)
        if let station = player.currentStation {
            HistoryStore.shared.addFromShazam(match, stationName: station.name)
        }
        updateNowPlayingButtons()
    }
}
