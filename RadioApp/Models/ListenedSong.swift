import Foundation

struct ListenedSong: Identifiable, Codable {
    var id: UUID
    var title: String
    var artist: String?
    var stationName: String
    var listenedAt: Date
    var artworkURL: String?
    var appleMusicURL: String?
    var source: Source

    enum Source: String, Codable {
        case icy      // detected automatically from stream metadata
        case shazam   // identified by the user via ShazamKit
    }

    var displayTitle: String { title }
    var displayArtist: String? { artist }

    /// Parses "Artist - Title" strings from ICY streams
    static func fromICY(raw: String, station: Station) -> ListenedSong {
        let parts = raw.components(separatedBy: " - ")
        let title: String
        let artist: String?
        if parts.count >= 2 {
            artist = parts[0].trimmingCharacters(in: .whitespaces)
            title  = parts[1...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        } else {
            artist = nil
            title  = raw.trimmingCharacters(in: .whitespaces)
        }
        return ListenedSong(
            id: UUID(),
            title: title,
            artist: artist,
            stationName: station.name,
            listenedAt: Date(),
            artworkURL: nil,
            appleMusicURL: nil,
            source: .icy
        )
    }
}
