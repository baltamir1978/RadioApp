import Foundation
import Combine
import ShazamKit
import SwiftUI

final class HistoryStore: ObservableObject {
    @Published private(set) var songs: [ListenedSong] = []

    private let maxEntries = 500
    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("history.json")
    }()

    init() { load() }

    // MARK: - Public API

    func addFromICY(raw: String, station: Station) {
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Avoid duplicate consecutive entries for the same track on the same station
        if let last = songs.first,
           last.stationName == station.name,
           last.title == ListenedSong.fromICY(raw: raw, station: station).title,
           last.source == .icy {
            return
        }
        insert(ListenedSong.fromICY(raw: raw, station: station))
    }

    func addFromShazam(_ item: SHMatchedMediaItem, station: Station) {
        let song = ListenedSong(
            id: UUID(),
            title: item.title ?? "Desconocido",
            artist: item.artist,
            stationName: station.name,
            listenedAt: Date(),
            artworkURL: item.artworkURL?.absoluteString,
            appleMusicURL: item.appleMusicURL?.absoluteString,
            source: .shazam
        )
        // Upgrade an existing ICY entry for the same track if present recently
        if let idx = songs.firstIndex(where: {
            $0.stationName == station.name &&
            $0.source == .icy &&
            Date().timeIntervalSince($0.listenedAt) < 120
        }) {
            songs[idx] = song
            save()
            return
        }
        insert(song)
    }

    func delete(at offsets: IndexSet) {
        songs.remove(atOffsets: offsets)
        save()
    }

    func clearAll() {
        songs.removeAll()
        save()
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
              let decoded = try? JSONDecoder().decode([ListenedSong].self, from: data)
        else { return }
        songs = decoded
    }
}
