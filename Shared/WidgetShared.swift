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
    /// The song's cover, when one was found; the widget falls back to the logo.
    var coverURL: String? = nil
    var lyrics: SongLyrics? = nil
    var lyricsPending: Bool = false
    /// When the lyrics' clock starts: the song's start with the app's lead and the station's
    /// adjustment already applied. Only drives the lyrics when `songStartIsExact`.
    var songStartedAt: Date? = nil
    var songStartIsExact: Bool = false
}

// MARK: - Lyrics

nonisolated struct LyricLine: Codable, Sendable, Hashable {
    /// Seconds from the start of the song.
    var time: Double
    var text: String
}

nonisolated struct SongLyrics: Codable, Sendable, Equatable {
    /// Time-stamped lines; empty when the source only has plain text.
    var synced: [LyricLine]
    var plain: [String]
    var isInstrumental: Bool
    /// The song's length in seconds, when the source knows it.
    var duration: Double? = nil

    var isEmpty: Bool { synced.isEmpty && plain.isEmpty }

    /// Lines to display, whichever form we have.
    var lines: [String] {
        synced.isEmpty ? plain : synced.map(\.text)
    }

    /// Index of the line being sung `elapsed` seconds into the song, or nil before the first.
    func lineIndex(at elapsed: Double) -> Int? {
        guard !synced.isEmpty else { return nil }
        var found: Int?
        for (i, line) in synced.enumerated() {
            if line.time <= elapsed { found = i } else { break }
        }
        return found
    }
}

/// A station the widget can launch via the `radioapp://play?u=<streamURL>` deep link.
struct WidgetStation: Codable, Identifiable {
    var name: String
    var streamURL: String
    var logoURL: String?
    var initials: String

    var id: String { streamURL }
}
