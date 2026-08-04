import AppIntents
import Foundation

// MARK: - Station entity (what Siri matches against)

nonisolated struct StationEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "intent_station_type")
    static let defaultQuery = StationQuery()

    /// Stable identifier = the stream URL (the Station UUID is regenerated on cold start).
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

nonisolated struct StationQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async -> [StationEntity] {
        await snapshot().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async -> [StationEntity] {
        await snapshot()
    }

    /// Matches a spoken/typed name, ignoring case and accents.
    func entities(matching string: String) async -> [StationEntity] {
        let q = Self.normalize(string)
        return await snapshot().filter { Self.normalize($0.name).contains(q) }
    }

    private func snapshot() async -> [StationEntity] {
        await MainActor.run {
            StationsStore.shared.stations.map { StationEntity(id: $0.streamURL, name: $0.name) }
        }
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
}

// MARK: - Play intent

struct PlayStationIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "intent_play_title" }
    nonisolated static var description: IntentDescription { IntentDescription("intent_play_desc") }
    /// Launch the app so audio plays in its process.
    nonisolated static var openAppWhenRun: Bool { true }

    @Parameter(title: "intent_station_type")
    var station: StationEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let s = StationsStore.shared.stations.first(where: { $0.streamURL == station.id }) {
            RadioPlayer.shared.play(s)
        }
        let spoken = String(format: NSLocalizedString("intent_playing_dialog", comment: ""), station.name)
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

// MARK: - Siri / Shortcuts phrases

nonisolated struct RadioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayStationIntent(),
            phrases: [
                "Pon \(\.$station) en \(.applicationName)",
                "Pon \(\.$station) en la \(.applicationName)",
                "Reproduce \(\.$station) en \(.applicationName)",
                "Escucha \(\.$station) en \(.applicationName)"
            ],
            shortTitle: "Reproducir emisora",
            systemImageName: "radio"
        )
    }
}
