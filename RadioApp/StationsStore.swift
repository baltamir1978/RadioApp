import Foundation
import Combine
import SwiftUI

@MainActor
class StationsStore: ObservableObject {
    @Published var stations: [Station] = []

    private let saveKey = "saved_stations"

    init() {
        load()
        if stations.isEmpty {
            stations = Station.defaults
        }
    }

    func add(_ station: Station) {
        guard !contains(station) else { return }
        stations.append(station)
        save()
    }

    func remove(at offsets: IndexSet) {
        stations.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        stations.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func update(_ old: Station, with new: Station) {
        guard let idx = stations.firstIndex(where: { $0.id == old.id }) else { return }
        stations[idx] = new
        save()
    }

    func remove(_ station: Station) {
        stations.removeAll { $0.id == station.id }
        save()
    }

    func contains(_ station: Station) -> Bool {
        stations.contains(where: { $0.streamURL == station.streamURL })
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([Station].self, from: data) else { return }
        stations = decoded
    }
}

extension Station {
    static let defaults: [Station] = [
        Station(name: "Vive Segovia",
                streamURL: "https://streaming.viveradio.es/vivesegovia",
                country: "ES", genre: "Regional"),
        Station(name: "Cassette FM",
                streamURL: "https://stream.costafm.es/listen/cassettefm_-_em/radio.mp3",
                country: "ES", genre: "Pop"),
        Station(name: "Cadena 100",
                streamURL: "https://cadena100-cope-rrcast.flumotion.com/cope/cadena100-low.mp3",
                logoURL: "https://www.cadena100.es/estaticos/apple-touch-icon-192x192.png",
                country: "ES", genre: "Pop"),
        Station(name: "Kiss FM",
                streamURL: "http://kissfm.kissfmradio.cires21.com/kissfm.mp3",
                country: "ES", genre: "Dance"),
        Station(name: "La Indie",
                streamURL: "https://stream.emisorasmusicales.net/listen/la_indie/laindie.mp3",
                country: "ES", genre: "Indie"),
        Station(name: "Los 40 Classic",
                streamURL: "http://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_CLASSIC.mp3",
                logoURL: "https://los40es00.epimg.net/iconos/v1.x/v1.0/promos/promo_og_los40.png",
                country: "ES", genre: "Pop"),
        Station(name: "SER Oriente",
                streamURL: "https://playerservices.streamtheworld.com/api/livestream-redirect/SER_ASO_ORIENTE.mp3",
                logoURL: "https://cadenaser00.epimg.net/favicon.png",
                country: "ES", genre: "Talk"),
    ]
}
