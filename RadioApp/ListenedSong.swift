import Foundation

/// A track that was playing on a station — captured automatically from the stream
/// metadata (ICY) or identified by the user with Shazam.
struct ListenedSong: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var artist: String?
    var stationName: String
    var listenedAt: Date
    var artworkURL: String?
    var appleMusicURL: String?
    var source: Source
    /// User explicitly kept this auto-captured track (heart). Shazam tracks are
    /// always treated as intentional regardless of this flag.
    var favorite: Bool = false

    enum Source: String, Codable {
        case icy      // detected automatically from stream metadata
        case shazam   // identified by the user via ShazamKit
    }

    /// Highlighted in the history: identified by Shazam or explicitly hearted.
    var isHighlighted: Bool { source == .shazam || favorite }

    init(id: UUID = UUID(), title: String, artist: String? = nil, stationName: String,
         listenedAt: Date, artworkURL: String? = nil, appleMusicURL: String? = nil,
         source: Source, favorite: Bool = false) {
        self.id = id
        self.title = title
        self.artist = artist
        self.stationName = stationName
        self.listenedAt = listenedAt
        self.artworkURL = artworkURL
        self.appleMusicURL = appleMusicURL
        self.source = source
        self.favorite = favorite
    }

    // Backwards-compatible decoding: existing history.json has no `favorite` key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        stationName = try c.decode(String.self, forKey: .stationName)
        listenedAt = try c.decode(Date.self, forKey: .listenedAt)
        artworkURL = try c.decodeIfPresent(String.self, forKey: .artworkURL)
        appleMusicURL = try c.decodeIfPresent(String.self, forKey: .appleMusicURL)
        source = try c.decode(Source.self, forKey: .source)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    }
}
