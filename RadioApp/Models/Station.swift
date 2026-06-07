import Foundation

struct Station: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var url: String
    var logoURL: String?
    var order: Int

    init(id: UUID = UUID(), name: String, url: String, logoURL: String? = nil, order: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.logoURL = logoURL
        self.order = order
    }

    /// Two-letter initials for the fallback logo
    var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
