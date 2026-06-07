import Foundation

struct RadioBrowserStation: Identifiable, Decodable {
    let id: String
    let name: String
    let streamURL: String
    let favicon: String?
    let country: String?
    let countryCode: String?
    let language: String?
    let tags: String?
    let codec: String?
    let bitrate: Int?
    let votes: Int?
    let clickCount: Int?

    enum CodingKeys: String, CodingKey {
        case id          = "stationuuid"
        case name
        case streamURL   = "url_resolved"
        case favicon
        case country
        case countryCode = "countrycode"
        case language
        case tags
        case codec
        case bitrate
        case votes
        case clickCount  = "clickcount"
    }

    var flagEmoji: String {
        guard let code = countryCode, code.count == 2 else { return "📻" }
        let base: UInt32 = 127397
        return code.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(base + $0.value)
        }.map(String.init).joined()
    }

    var tagList: [String] {
        tags?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
    }

    func toStation() -> Station {
        Station(
            name: name.trimmingCharacters(in: .whitespaces),
            url: streamURL,
            logoURL: favicon?.isEmpty == false ? favicon : nil
        )
    }
}
