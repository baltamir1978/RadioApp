import Foundation

struct RadioBrowserStation: Decodable, Identifiable {
    let stationuuid: String
    let name: String
    let url_resolved: String
    let favicon: String?
    let countrycode: String?
    let tags: String?

    var id: String { stationuuid }

    var toStation: Station {
        Station(
            name: name,
            streamURL: url_resolved,
            logoURL: (favicon?.isEmpty == false) ? favicon : nil,
            country: countrycode,
            genre: tags?.split(separator: ",").first.map(String.init),
            stationuuid: stationuuid
        )
    }
}

actor RadioBrowserService {
    static let shared = RadioBrowserService()
    private let baseURL = "https://de1.api.radio-browser.info/json"

    private init() {}

    func search(name: String, country: String? = nil, limit: Int = 40) async throws -> [RadioBrowserStation] {
        var components = URLComponents(string: "\(baseURL)/stations/search")!
        var params: [URLQueryItem] = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "votes"),
            URLQueryItem(name: "reverse", value: "true"),
        ]
        if let country, !country.isEmpty {
            params.append(URLQueryItem(name: "countrycode", value: country))
        }
        components.queryItems = params
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode([RadioBrowserStation].self, from: data)
    }

    func topStations(country: String? = nil, limit: Int = 50) async throws -> [RadioBrowserStation] {
        var components = URLComponents(string: "\(baseURL)/stations/topvote")!
        var params: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "hidebroken", value: "true"),
        ]
        if let country, !country.isEmpty {
            params.append(URLQueryItem(name: "countrycode", value: country))
        }
        components.queryItems = params
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode([RadioBrowserStation].self, from: data)
    }
}
