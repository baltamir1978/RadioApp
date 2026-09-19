import WidgetKit
import SwiftUI

// MARK: - Timeline

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
    let logo: Data?
    /// The song's cover, when the app found one; the large sizes show it instead of the logo.
    var cover: Data? = nil
    /// Line of the synced lyrics being sung at `date`, if known.
    var lyricIndex: Int? = nil
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

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NowPlayingEntry) -> Void) {
        Task { completion(await makeEntries().first!) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NowPlayingEntry>) -> Void) {
        // No refresh policy of our own: the app reloads the widget whenever the song, station or
        // play state changes. Only the lyrics move by the clock, and those are in the entries.
        Task { completion(Timeline(entries: await makeEntries(), policy: .never)) }
    }

    /// One entry for right now, plus one per synced lyric line still to come, so the lyrics
    /// step along with the song without the app having to wake the widget.
    private func makeEntries() async -> [NowPlayingEntry] {
        let snap = WidgetShared.loadNowPlaying()
        let logo = await loadLogoData(snap?.logoURL)
        let cover = await loadLogoData(snap?.coverURL)
        let now = Date()
        guard let snap, snap.isPlaying, snap.track != nil,
              let start = snap.songStartedAt, snap.songStartIsExact,
              let lyrics = snap.lyrics, !lyrics.synced.isEmpty else {
            return [NowPlayingEntry(date: now, snapshot: snap, logo: logo, cover: cover)]
        }
        var entries = [NowPlayingEntry(date: now, snapshot: snap, logo: logo, cover: cover,
                                       lyricIndex: lyrics.lineIndex(at: now.timeIntervalSince(start)))]
        for (index, line) in lyrics.synced.enumerated() {
            let date = start.addingTimeInterval(line.time)
            guard date > now else { continue }
            entries.append(NowPlayingEntry(date: date, snapshot: snap, logo: logo, cover: cover, lyricIndex: index))
            // A song has well under this many lines; the cap only guards against a broken file.
            if entries.count >= 150 { break }
        }
        return entries
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
        case .systemLarge, .systemExtraLarge:
            if entry.snapshot != nil { large } else { placeholder }
        default:
            home
        }
    }

    // MARK: Large: the song and its lyrics

    /// The cover when there is one, else the station's logo.
    private var artworkImage: Image? {
        if let data = entry.cover, let ui = UIImage(data: data) { return Image(uiImage: ui) }
        return logoImage
    }

    private var large: some View {
        let extra = family == .systemExtraLarge
        let side: CGFloat = extra ? 150 : 96
        return Group {
            if extra {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        artwork(size: side)
                        songText
                    }
                    .frame(width: side + 40, alignment: .leading)
                    WidgetLyrics(snapshot: entry.snapshot, lyricIndex: entry.lyricIndex, maxLines: 12)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        artwork(size: side)
                        songText
                    }
                    WidgetLyrics(snapshot: entry.snapshot, lyricIndex: entry.lyricIndex, maxLines: 7)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Color.wBackground, for: .widget)
    }

    @ViewBuilder
    private var songText: some View {
        if let snap = entry.snapshot {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: snap.isPlaying ? "dot.radiowaves.left.and.right" : "pause.fill")
                        .font(.caption2)
                    Text(snap.stationName).font(.caption.weight(.semibold)).lineLimit(1)
                }
                .foregroundStyle(Color.wBrand)
                if let track = snap.track, !track.isEmpty {
                    Text(track).font(.headline).lineLimit(2)
                    if let artist = snap.artist, !artist.isEmpty {
                        Text(artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text(snap.isPlaying
                         ? NSLocalizedString("live", value: "En directo", comment: "")
                         : NSLocalizedString("paused", value: "En pausa", comment: ""))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func artwork(size: CGFloat) -> some View {
        ZStack {
            if let img = artworkImage {
                img.resizable().aspectRatio(contentMode: .fill).background(Color.white)
            } else {
                Color.wSurface
                Image(systemName: "radio.fill").font(.largeTitle).foregroundStyle(Color.wBrand)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        .accessibilityHidden(true)
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

// MARK: - Lyrics

/// The lyrics window: the line being sung, one before it and the ones coming up.
///
/// A widget can't scroll or animate, so the timeline carries one entry per synced line and each
/// entry is drawn with its own `lyricIndex` — the window steps along as the song plays.
private struct WidgetLyrics: View {
    let snapshot: NowPlayingSnapshot?
    let lyricIndex: Int?
    let maxLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(NSLocalizedString("lyrics_title", value: "Letra", comment: ""), systemImage: "quote.bubble")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.wBrand)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot, let track = snapshot.track, !track.isEmpty {
            if let lyrics = snapshot.lyrics, lyrics.isInstrumental {
                note("lyrics_instrumental")
            } else if let lyrics = snapshot.lyrics, !lyrics.isEmpty {
                lines(lyrics)
            } else if snapshot.lyricsPending {
                note("lyrics_searching")
            } else {
                note("lyrics_none")
            }
        } else {
            note("lyrics_wait_title")
        }
    }

    private func note(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lines(_ lyrics: SongLyrics) -> some View {
        let all = lyrics.lines
        let current = lyricIndex
        // Keep one sung line above the current one for context.
        let first = max(0, min((current ?? 0) - 1, all.count - maxLines))
        let window = Array(all.enumerated()).dropFirst(first).prefix(maxLines)
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(window), id: \.offset) { index, text in
                let isCurrent = index == current
                let isPast = current.map { index < $0 } ?? false
                Text(text.isEmpty ? "♪" : text)
                    .font(isCurrent ? .body.weight(.semibold) : .subheadline)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(Color.primary)
                                     : isPast ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    .lineLimit(isCurrent ? 2 : 1)
            }
        }
    }
}

// MARK: - Widget

struct NowPlayingWidget: Widget {
    let kind = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .widgetURL(URL(string: "radioapp://nowplaying"))
        }
        .configurationDisplayName(NSLocalizedString("widget_now_playing_title", value: "Sonando ahora", comment: ""))
        .description(NSLocalizedString("widget_now_playing_desc", value: "Muestra la emisora y la canción que estás escuchando y, en tamaño grande, su letra. Tócalo para abrir la app.", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular])
    }
}
