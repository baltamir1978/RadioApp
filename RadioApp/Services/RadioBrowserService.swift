import Foundation
import Combine

final class RadioBrowserService: ObservableObject {
    @Published var results: [RadioBrowserStation] = []
    @Published var isLoading = false
    @Published var error: String?

    // Radio Browser mirrors — picked randomly for load balancing
    private let servers = [
        "de1.api.radio-browser.info",
        "nl1.api.radio-browser.info",
        "at1.api.radio-browser.info",
    ]

    private var baseURL: String {
        "https://\(servers.randomElement()!)/json"
    }

    private var currentTask: Task<Void, Never>?

    // MARK: - Search

    func search(query: String, countryCode: String? = nil, language: String? = nil) {
        currentTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        currentTask = Task {
            await performSearch(query: query, countryCode: countryCode, language: language)
        }
    }

    func loadTopStations(countryCode: String? = nil) {
        currentTask?.cancel()
        currentTask = Task {
            await performTopStations(countryCode: countryCode)
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Private

    @MainActor
    private func performSearch(query: String, countryCode: String?, language: String?) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        var components = URLComponents(string: "\(baseURL)/stations/search")!
        var items: [URLQueryItem] = [
            .init(name: "name",        value: query),
            .init(name: "codec",       value: "MP3"),
            .init(name: "hidebroken",  value: "true"),
            .init(name: "order",       value: "clickcount"),
            .init(name: "reverse",     value: "true"),
            .init(name: "limit",       value: "40"),
        ]
        if let cc = countryCode, !cc.isEmpty { items.append(.init(name: "countrycode", value: cc)) }
        if let lang = language, !lang.isEmpty { items.append(.init(name: "language", value: lang)) }
        components.queryItems = items

        await fetch(url: components.url!)
    }

    @MainActor
    private func performTopStations(countryCode: String?) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        var components = URLComponents(string: "\(baseURL)/stations/search")!
        var items: [URLQueryItem] = [
            .init(name: "codec",      value: "MP3"),
            .init(name: "hidebroken", value: "true"),
            .init(name: "order",      value: "clickcount"),
            .init(name: "reverse",    value: "true"),
            .init(name: "limit",      value: "40"),
        ]
        if let cc = countryCode, !cc.isEmpty { items.append(.init(name: "countrycode", value: cc)) }
        components.queryItems = items

        await fetch(url: components.url!)
    }

    @MainActor
    private func fetch(url: URL) async {
        do {
            var request = URLRequest(url: url)
            request.setValue("RadioApp/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            results = try JSONDecoder().decode([RadioBrowserStation].self, from: data)
        } catch is CancellationError {
            // Silently ignore task cancellation
        } catch {
            self.error = error.localizedDescription
            results = []
        }
    }
}
