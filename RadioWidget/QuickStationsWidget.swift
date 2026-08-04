import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Configuration

/// One of the user's stations, offered as a choice when editing the widget.
/// Identified by stream URL because `Station.id` is regenerated on a cold start.
nonisolated struct QuickStationEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "intent_station_type")
    static let defaultQuery = QuickStationQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

nonisolated struct QuickStationQuery: EntityQuery {
    func entities(for identifiers: [String]) async -> [QuickStationEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async -> [QuickStationEntity] { all() }

    private func all() -> [QuickStationEntity] {
        WidgetShared.loadStations().map { QuickStationEntity(id: $0.streamURL, name: $0.name) }
    }
}

/// Backs the widget's edit screen: one station per slot, left to right.
/// Leaving every slot empty keeps the original behaviour — the first four stations.
struct SelectQuickStationsIntent: WidgetConfigurationIntent {
    nonisolated static var title: LocalizedStringResource { "intent_widget_title" }
    nonisolated static var description: IntentDescription { IntentDescription("intent_widget_desc") }

    @Parameter(title: "intent_slot_1") var slot1: QuickStationEntity?
    @Parameter(title: "intent_slot_2") var slot2: QuickStationEntity?
    @Parameter(title: "intent_slot_3") var slot3: QuickStationEntity?
    @Parameter(title: "intent_slot_4") var slot4: QuickStationEntity?

    nonisolated var chosenIDs: [String] { [slot1, slot2, slot3, slot4].compactMap(\.?.id) }
}

// MARK: - Timeline

struct QuickItem: Identifiable {
    let name: String
    let streamURL: String
    let initials: String
    let logo: Data?
    var id: String { streamURL }
}

struct QuickStationsEntry: TimelineEntry {
    let date: Date
    let items: [QuickItem]
}

struct QuickStationsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickStationsEntry {
        // Representative sample so the gallery preview shows the launch grid.
        let demo = [("Cadena 100", "C1"), ("Kiss FM", "KF"), ("Los 40", "40"), ("SER", "SE")]
        return QuickStationsEntry(date: Date(), items: demo.map {
            QuickItem(name: $0.0, streamURL: "radioapp://demo", initials: $0.1, logo: nil)
        })
    }

    func snapshot(for configuration: SelectQuickStationsIntent, in context: Context) async -> QuickStationsEntry {
        await makeEntry(for: configuration)
    }

    func timeline(for configuration: SelectQuickStationsIntent, in context: Context) async -> Timeline<QuickStationsEntry> {
        Timeline(entries: [await makeEntry(for: configuration)], policy: .never)
    }

    private func makeEntry(for configuration: SelectQuickStationsIntent) async -> QuickStationsEntry {
        var items: [QuickItem] = []
        for s in resolve(configuration) {
            items.append(QuickItem(name: s.name, streamURL: s.streamURL,
                                   initials: s.initials, logo: await loadLogoData(s.logoURL)))
        }
        return QuickStationsEntry(date: Date(), items: items)
    }

    /// Chosen slots win; an unconfigured widget falls back to the top of the list.
    /// Stations deleted in the app since the widget was set up simply drop out.
    private func resolve(_ configuration: SelectQuickStationsIntent) -> [WidgetStation] {
        let stations = WidgetShared.loadStations()
        let ids = configuration.chosenIDs
        guard !ids.isEmpty else { return Array(stations.prefix(4)) }
        return ids.compactMap { id in stations.first { $0.streamURL == id } }
    }
}

// MARK: - Views

struct QuickStationsWidgetView: View {
    var entry: QuickStationsEntry
    @Environment(\.widgetFamily) private var family

    private var count: Int { family == .systemSmall ? 2 : 4 }

    var body: some View {
        Group {
            if entry.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "radio").font(.system(size: 32)).foregroundStyle(Color.wBrand)
                    Text(NSLocalizedString("no_stations", value: "Sin emisoras", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("my_stations", value: "Mis emisoras", comment: ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.wBrand)
                    HStack(spacing: 10) {
                        ForEach(entry.items.prefix(count)) { item in
                            stationButton(item)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .containerBackground(Color.wBackground, for: .widget)
    }

    private func stationButton(_ item: QuickItem) -> some View {
        Link(destination: playDeepLink(streamURL: item.streamURL) ?? URL(string: "radioapp://open")!) {
            VStack(spacing: 5) {
                ZStack {
                    if let data = item.logo, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill).background(Color.white)
                    } else {
                        // Not white on the accent: in dark mode that pair is 1.8:1.
                        Color.wBrand
                        Text(item.initials)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.wBackground)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(String(format: NSLocalizedString("a11y_play_station", value: "Escuchar %@", comment: ""),
                                   item.name))
    }
}

// MARK: - Widget

struct QuickStationsWidget: Widget {
    let kind = "QuickStationsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectQuickStationsIntent.self,
                               provider: QuickStationsProvider()) { entry in
            QuickStationsWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_stations_title", value: "Lanzar emisora", comment: ""))
        .description(NSLocalizedString("widget_stations_desc", value: "Tus emisoras en accesos directos: mantén pulsado el widget para elegir cuáles.", comment: ""))
        .supportedFamilies([.systemMedium])
    }
}
