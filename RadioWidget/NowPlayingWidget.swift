import WidgetKit
import SwiftUI

// MARK: - Timeline

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
    let logo: Data?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        // Representative sample so the widget gallery shows what this widget does.
        NowPlayingEntry(
            date: Date(),
            snapshot: NowPlayingSnapshot(stationName: "Cadena 100", track: "Canción en directo",
                                         artist: "Artista", logoURL: nil, isPlaying: true),
            logo: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        Task { completion(await makeEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        Task { completion(Timeline(entries: [await makeEntry()], policy: .never)) }
    }

    private func makeEntry() async -> NowPlayingEntry {
        let snap = WidgetShared.loadNowPlaying()
        return NowPlayingEntry(date: Date(), snapshot: snap, logo: await loadLogoData(snap?.logoURL))
    }
}

/// Downloads a logo (small) for embedding in the entry — widgets can't load remote images lazily.
func loadLogoData(_ urlString: String?) async -> Data? {
    guard let urlString, let url = URL(string: urlString) else { return nil }
    return try? await URLSession.shared.data(from: url).0
}

// MARK: - Views

struct NowPlayingWidgetView: View {
    var entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessory
        default:
            home
        }
    }

    private var logoImage: Image? {
        if let data = entry.logo, let ui = UIImage(data: data) { return Image(uiImage: ui) }
        return nil
    }

    @ViewBuilder
    private var home: some View {
        if let snap = entry.snapshot {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    logo(size: 44)
                    if family != .systemSmall {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snap.stationName)
                                .font(.headline)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Image(systemName: snap.isPlaying ? "dot.radiowaves.left.and.right" : "pause.fill")
                                    .font(.caption2)
                                Text(snap.isPlaying
                                     ? NSLocalizedString("live", value: "En directo", comment: "")
                                     : NSLocalizedString("paused", value: "En pausa", comment: ""))
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.wBrand)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 2) {
                    if let track = snap.track, !track.isEmpty {
                        Text(track)
                            .font(family == .systemSmall ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .lineLimit(2)
                        if let artist = snap.artist, !artist.isEmpty, family != .systemSmall {
                            Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else if family == .systemSmall {
                        Text(snap.stationName).font(.caption.weight(.semibold)).lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(Color.wBackground, for: .widget)
        } else {
            placeholder
        }
    }

    private var accessory: some View {
        HStack(spacing: 6) {
            Image(systemName: "radio.fill")
            if let snap = entry.snapshot {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snap.stationName).font(.headline).lineLimit(1)
                    if let track = snap.track, !track.isEmpty {
                        Text(track).font(.caption).lineLimit(1)
                    }
                }
            } else {
                Text("Radio").font(.headline)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "radio")
                .font(.system(size: 34))
                .foregroundStyle(Color.wBrand)
            Text(NSLocalizedString("widget_choose_station", value: "Elige una emisora", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color.wBackground, for: .widget)
    }

    @ViewBuilder
    private func logo(size: CGFloat) -> some View {
        ZStack {
            if let img = logoImage {
                img.resizable().aspectRatio(contentMode: .fill).background(Color.white)
            } else {
                Color.wSurface
                Image(systemName: "radio.fill").foregroundStyle(Color.wBrand)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - Widget

struct NowPlayingWidget: Widget {
    let kind = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .widgetURL(URL(string: "radioapp://open"))
        }
        .configurationDisplayName(NSLocalizedString("widget_now_playing_title", value: "Sonando ahora", comment: ""))
        .description(NSLocalizedString("widget_now_playing_desc", value: "Muestra la emisora y la canción que estás escuchando. Tócalo para abrir la app.", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
