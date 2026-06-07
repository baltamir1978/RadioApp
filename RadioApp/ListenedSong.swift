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

    enum Source: String, Codable {
        case icy      // detected automatically from stream metadata
        case shazam   // identified by the user via ShazamKit
    }
}
