import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Data shared between the app and its widget extension through an App Group.
enum WidgetShared {
    static let suiteName = "group.Altamirano.RadioApp"
    static let nowPlayingKey = "widget_now_playing"
    static let stationsKey = "widget_stations"

    static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    // MARK: Now playing

    static func saveNowPlaying(_ snapshot: NowPlayingSnapshot?) {
        guard let d = defaults else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            d.set(data, forKey: nowPlayingKey)
        } else {
            d.removeObject(forKey: nowPlayingKey)
        }
        reload()
    }

    static func loadNowPlaying() -> NowPlayingSnapshot? {
        guard let d = defaults, let data = d.data(forKey: nowPlayingKey) else { return nil }
        return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
    }

    // MARK: Stations (quick launch)

    static func saveStations(_ stations: [WidgetStation]) {
        guard let d = defaults, let data = try? JSONEncoder().encode(stations) else { return }
        d.set(data, forKey: stationsKey)
        reload()
    }

    static func loadStations() -> [WidgetStation] {
        guard let d = defaults, let data = d.data(forKey: stationsKey),
              let stations = try? JSONDecoder().decode([WidgetStation].self, from: data) else { return [] }
        return stations
    }

    static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// Snapshot of what's playing, surfaced by the Now Playing widget.
struct NowPlayingSnapshot: Codable {
    var stationName: String
    var track: String?
    var artist: String?
    var logoURL: String?
    var isPlaying: Bool
}

/// A station the widget can launch via the `radioapp://play?u=<streamURL>` deep link.
struct WidgetStation: Codable, Identifiable {
    var name: String
    var streamURL: String
    var logoURL: String?
    var initials: String

    var id: String { streamURL }
}
