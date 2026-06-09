import Foundation
import Combine
import ShazamKit
import SwiftUI

/// Persistent log of the songs heard across stations.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var songs: [ListenedSong] = []

    private let maxEntries = 500
    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("history.json")
    }()

    private init() { load() }

    // MARK: - Capture

    /// Auto-saves a track read from stream (ICY) metadata, skipping consecutive duplicates.
    func addFromICY(track: String, artist: String?, stationName: String) {
        let title = track.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if let last = songs.first,
           last.stationName == stationName, last.title == title, last.source == .icy {
            return
        }
        insert(ListenedSong(title: title, artist: artist,
                            stationName: stationName, listenedAt: Date(), source: .icy))
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
}
