import Foundation
import Combine
import SwiftUI

final class StationsStore: ObservableObject {
    @Published var stations: [Station] = []

    private let key = "saved_stations"

    init() {
        load()
        if stations.isEmpty {
            stations = Station.defaults
        }
    }

    func add(_ station: Station) {
        var s = station
        s.order = stations.count
        stations.append(s)
        save()
    }

    func update(_ station: Station) {
        guard let idx = stations.firstIndex(where: { $0.id == station.id }) else { return }
        stations[idx] = station
        save()
    }

    func delete(at offsets: IndexSet) {
        stations.remove(atOffsets: offsets)
        reorder()
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        stations.move(fromOffsets: source, toOffset: destination)
        reorder()
        save()
    }

    private func reorder() {
        for i in stations.indices { stations[i].order = i }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Station].self, from: data)
        else { return }
        stations = decoded.sorted { $0.order < $1.order }
    }
}

extension Station {
    static let defaults: [Station] = [
        Station(name: "Radio Nacional", url: "https://rtveliveaudio.akamaized.net/rne/rne1/master.m3u8", order: 0),
        Station(name: "Los 40", url: "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40.mp3", order: 1),
        Station(name: "Cadena SER", url: "https://playerservices.streamtheworld.com/api/livestream-redirect/SER_MADRID.mp3", order: 2),
    ]
}
