import Foundation

struct Station: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var streamURL: String
    var logoURL: String?
    var country: String?
    var genre: String?
    var stationuuid: String?

    var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}
