import Foundation
import Combine
import ShazamKit
import SwiftUI

/// Persistent log of the songs heard across stations.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var songs: [ListenedSong] = []

    /// Per-station titles the user chose to never auto-save again (station slogans /
    /// jingles like "la mejor variedad musical"). Keeps the readable title so the
    /// user can review and undo entries from the ignore list.
    @Published private(set) var ignored: [IgnoredTitle] = []

    /// Cover art resolved before its history entry existed; consumed by `addFromICY`.
    private var pendingArtwork: (key: String, url: String, appleMusicURL: String?)?

    private let maxEntries = 500
    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("history.json")
    }()
    private let ignoredFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ignored_titles.json")
    }()

    private init() { load(); loadIgnored() }

    // MARK: - Ignore list

    /// Whether an auto-captured title is on the user's per-station ignore list.
    func isIgnored(title: String, stationName: String) -> Bool {
        let key = IgnoredTitle.key(station: stationName, title: title)
        return ignored.contains { $0.key == key }
    }

    /// Removes an entry from the ignore list, so its title will be auto-saved again.
    func unignore(_ entry: IgnoredTitle) {
        ignored.removeAll { $0.id == entry.id }
        saveIgnored()
    }

    // MARK: - Capture

    /// Auto-saves a track read from stream (ICY) metadata, skipping consecutive duplicates
    /// and titles the user has chosen to ignore for this station.
    func addFromICY(track: String, artist: String?, stationName: String) {
        let title = track.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard !isIgnored(title: title, stationName: stationName) else { return }
        if let last = songs.first,
           last.stationName == stationName, last.title == title, last.source == .icy {
            return
        }
        // A cover that was resolved before this entry existed is claimed here.
        var artwork: String?
        var appleMusic: String?
        if let pending = pendingArtwork,
           pending.key == IgnoredTitle.key(station: stationName, title: title) {
            artwork = pending.url
            appleMusic = pending.appleMusicURL
            pendingArtwork = nil
        }
        insert(ListenedSong(title: title, artist: artist,
                            stationName: stationName, listenedAt: Date(),
                            artworkURL: artwork, appleMusicURL: appleMusic, source: .icy))
    }

    /// Attaches the cover art resolved for a live track to its history entry, so the list
    /// keeps showing the image after the song is gone. Cover lookups are asynchronous and can
    /// land either side of the entry being created, so an image that arrives first is parked
    /// as `pendingArtwork` and picked up by the next matching `addFromICY`.
    func attachArtwork(url: String, appleMusicURL: String?, title: String, stationName: String) {
        let key = IgnoredTitle.key(station: stationName, title: title)
        if let idx = songs.firstIndex(where: {
            IgnoredTitle.key(station: $0.stationName, title: $0.title) == key
        }) {
            guard songs[idx].artworkURL == nil else { return }
            songs[idx].artworkURL = url
            if songs[idx].appleMusicURL == nil { songs[idx].appleMusicURL = appleMusicURL }
            save()
        } else {
            pendingArtwork = (key: key, url: url, appleMusicURL: appleMusicURL)
        }
    }

    /// Saves a Shazam match; upgrades a recent ICY entry for the same station if present.
    func addFromShazam(_ match: ShazamMatch, stationName: String) {
        let song = ListenedSong(
            title: match.title.isEmpty ? "—" : match.title,
            artist: match.artist.isEmpty ? nil : match.artist,
            stationName: stationName,
            listenedAt: Date(),
            artworkURL: match.artworkURL?.absoluteString,
            appleMusicURL: match.appleMusicURL?.absoluteString,
            source: .shazam
        )
        if let idx = songs.firstIndex(where: {
            $0.stationName == stationName && $0.source == .icy &&
            Date().timeIntervalSince($0.listenedAt) < 120
        }) {
            songs[idx] = song
            save()
            return
        }
        insert(song)
    }

    // MARK: - Edit

    func delete(at offsets: IndexSet) { songs.remove(atOffsets: offsets); save() }
    func clearAll() { songs.removeAll(); save() }

    /// Removes just this one entry.
    func delete(_ song: ListenedSong) {
        songs.removeAll { $0.id == song.id }
        save()
    }

    /// "Delete for good": ignores this title on its station from now on and purges every
    /// auto-captured copy already in history. Kept (♥) and Shazam entries are left alone.
    func ignoreAndPurge(_ song: ListenedSong) {
        let entry = IgnoredTitle(stationName: song.stationName, title: song.title)
        if !ignored.contains(where: { $0.key == entry.key }) {
            ignored.insert(entry, at: 0)
            saveIgnored()
        }
        songs.removeAll {
            $0.source == .icy && !$0.favorite &&
            IgnoredTitle.key(station: $0.stationName, title: $0.title) == entry.key
        }
        save()
    }

    /// Toggle the "kept" flag on an auto-captured track.
    func toggleFavorite(_ song: ListenedSong) {
        guard let idx = songs.firstIndex(where: { $0.id == song.id }) else { return }
        songs[idx].favorite.toggle()
        save()
    }

    /// Whether the track currently playing on `stationName` is already a kept favorite.
    func isFavorite(title: String?, stationName: String?) -> Bool {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let stationName else { return false }
        return songs.first(where: { $0.stationName == stationName && $0.title == title })?.favorite ?? false
    }

    /// Toggles the favorite flag for the now-playing track, capturing it into history
    /// first if it isn't there yet (e.g. favorited before any duplicate was logged).
    /// Returns the resulting favorite state.
    @discardableResult
    func toggleFavoriteForNowPlaying(title: String, artist: String?, stationName: String) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        if let idx = songs.firstIndex(where: { $0.stationName == stationName && $0.title == cleanTitle }) {
            songs[idx].favorite.toggle()
            save()
            return songs[idx].favorite
        }
        insert(ListenedSong(title: cleanTitle, artist: artist, stationName: stationName,
                            listenedAt: Date(), source: .icy, favorite: true))
        return true
    }

    // MARK: - Persistence

    private func insert(_ song: ListenedSong) {
        songs.insert(song, at: 0)
        if songs.count > maxEntries { songs = Array(songs.prefix(maxEntries)) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(songs) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ListenedSong].self, from: data) else { return }
        songs = decoded
    }

    private func saveIgnored() {
        if let data = try? JSONEncoder().encode(ignored) {
            try? data.write(to: ignoredFileURL, options: .atomic)
        }
    }

    private func loadIgnored() {
        guard let data = try? Data(contentsOf: ignoredFileURL),
              let decoded = try? JSONDecoder().decode([IgnoredTitle].self, from: data) else { return }
        ignored = decoded
    }
}

/// A station-specific title the user chose to keep out of the auto-saved history.
struct IgnoredTitle: Identifiable, Codable, Hashable {
    var stationName: String
    var title: String

    /// Match key: case- and accent-insensitive, scoped to the station.
    var key: String { Self.key(station: stationName, title: title) }
    var id: String { key }

    static func key(station: String, title: String) -> String {
        normalize(station) + "\n" + normalize(title)
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
