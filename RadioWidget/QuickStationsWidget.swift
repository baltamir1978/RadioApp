import WidgetKit
import SwiftUI

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

struct QuickStationsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStationsEntry {
        // Representative sample so the gallery preview shows the launch grid.
        let demo = [("Cadena 100", "C1"), ("Kiss FM", "KF"), ("Los 40", "40"), ("SER", "SE")]
        return QuickStationsEntry(date: Date(), items: demo.map {
            QuickItem(name: $0.0, streamURL: "radioapp://demo", initials: $0.1, logo: nil)
        })
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickStationsEntry) -> Void) {
        Task { completion(await makeEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStationsEntry>) -> Void) {
        Task { completion(Timeline(entries: [await makeEntry()], policy: .never)) }
    }

    private func makeEntry() async -> QuickStationsEntry {
        let stations = Array(WidgetShared.loadStations().prefix(4))
        var items: [QuickItem] = []
        for s in stations {
            items.append(QuickItem(name: s.name, streamURL: s.streamURL,
                                   initials: s.initials, logo: await loadLogoData(s.logoURL)))
        }
        return QuickStationsEntry(date: Date(), items: items)
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
                        Color.wBrand
                        Text(item.initials)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
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
    }
}

// MARK: - Widget

struct QuickStationsWidget: Widget {
    let kind = "QuickStationsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickStationsProvider()) { entry in
            QuickStationsWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_stations_title", value: "Lanzar emisora", comment: ""))
        .description(NSLocalizedString("widget_stations_desc", value: "Tus emisoras en accesos directos: toca una para empezar a escucharla.", comment: ""))
        .supportedFamilies([.systemMedium])
    }
}
