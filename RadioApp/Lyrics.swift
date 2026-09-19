import SwiftUI

/// Lyrics support, split by build.
///
/// Lyrics are copyrighted by music publishers, and showing them in an app on the App Store needs
/// a licence (or a licensed provider). RadioApp isn't public — it's installed from Xcode or
/// TestFlight — so the in-app lyrics (LRCLIB, time-synced) are compiled in: the
/// `LYRICS_EMBEDDED` compilation condition is set for the app target. Taking it out leaves the
/// link to Apple Music that a public build would need, and not a line of lyrics code.
enum LyricsFeature {
    #if LYRICS_EMBEDDED
    static let embedded = true
    #else
    static let embedded = false
    #endif
}

// MARK: - Link-out (build without lyrics)

enum LyricsLink {
    /// Best place to read this track's lyrics, opened externally. Prefers Shazam's exact
    /// Apple Music URL; otherwise falls back to an Apple Music text search.
    static func appleMusicURL(title: String, artist: String?, exact: URL?) -> URL? {
        if let exact { return exact }
        let terms = [artist, title]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !terms.isEmpty,
              let q = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://music.apple.com/search?term=\(q)")
    }
}

/// "View lyrics" in Apple Music, for a build without in-app lyrics.
struct LyricsLinkButton: View {
    let title: String
    var artist: String? = nil
    var appleMusicURL: URL? = nil

    var body: some View {
        if let url = LyricsLink.appleMusicURL(title: title, artist: artist, exact: appleMusicURL) {
            Link(destination: url) {
                Label(NSLocalizedString("view_lyrics", comment: ""), systemImage: "quote.bubble")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brand)
        }
    }
}

// MARK: - In-app lyrics

/// The song's lyrics, following it line by line when their timing is known.
struct LyricsPanel: View {
    @EnvironmentObject private var player: RadioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("lyrics_title", comment: ""))
                    .font(.headline)
                    .foregroundStyle(Color.brand)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if player.lyricsAreSynced { SyncAdjuster() }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if player.currentTrack == nil {
            note("lyrics_wait_title")
        } else if let lyrics = player.lyrics, lyrics.isInstrumental {
            note("lyrics_instrumental")
        } else if let lyrics = player.lyrics, !lyrics.synced.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                hint(player.songStartIsExact ? "lyrics_hint_synced" : "lyrics_hint_unplaced")
                SyncedLyrics(lyrics: lyrics, start: player.songStartIsExact ? player.lyricsStart : nil,
                             reduceMotion: reduceMotion) { player.syncLyrics(toLine: $0) }
            }
        } else if let lyrics = player.lyrics, !lyrics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                hint("lyrics_hint_plain")
                ScrollView {
                    Text(lyrics.lines.joined(separator: "\n"))
                        .font(.title3)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if player.lyricsPending {
            HStack(spacing: 8) {
                ProgressView()
                Text(NSLocalizedString("lyrics_searching", comment: "")).foregroundStyle(.secondary)
            }
        } else {
            note("lyrics_none")
        }
    }

    private func note(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.title3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func hint(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Moves the lyrics earlier or later for this station, half a second at a time.
private struct SyncAdjuster: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        HStack(spacing: 2) {
            Button { player.nudgeLyrics(by: -0.5) } label: {
                Image(systemName: "minus").frame(width: 36, height: 36)
            }
            .accessibilityLabel(NSLocalizedString("lyrics_later", comment: ""))
            Text(offsetText)
                .monospacedDigit()
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minWidth: 48)
                .accessibilityLabel(String(format: NSLocalizedString("lyrics_offset_a11y", comment: ""), offsetText))
            Button { player.nudgeLyrics(by: 0.5) } label: {
                Image(systemName: "plus").frame(width: 36, height: 36)
            }
            .accessibilityLabel(NSLocalizedString("lyrics_earlier", comment: ""))
            // Tapping a line leaves figures like +1.3 s that half-second steps never bring back.
            Button { player.resetLyricsOffset() } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 36, height: 36)
            }
            .accessibilityLabel(NSLocalizedString("lyrics_reset", comment: ""))
            .disabled(player.lyricsOffset == 0)
        }
        .buttonStyle(.borderless)
        .tint(Color.brand)
    }

    private var offsetText: String {
        player.lyricsOffset == 0 ? "±0 s"
            : player.lyricsOffset.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " s"
    }
}

/// Lyrics that follow the song: the line being sung is highlighted and kept in view. Every line
/// is also a button — tapping the one being sung puts the lyrics in step (`start` nil: the
/// position isn't known yet, so nothing is highlighted until then).
private struct SyncedLyrics: View {
    let lyrics: SongLyrics
    let start: Date?
    let reduceMotion: Bool
    let onPick: (Int) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let current = start.flatMap { lyrics.lineIndex(at: context.date.timeIntervalSince($0)) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(lyrics.synced.enumerated()), id: \.offset) { index, line in
                            Button { onPick(index) } label: {
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.title2.weight(index == current ? .bold : .regular))
                                    .foregroundStyle(index == current ? AnyShapeStyle(.primary)
                                                     : (current.map { index < $0 } ?? false)
                                                        ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(NSLocalizedString("lyrics_line_hint", comment: ""))
                            .accessibilityAddTraits(index == current ? .isSelected : [])
                            .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 40)
                }
                .onChange(of: current) { _, index in
                    guard let index else { return }
                    if reduceMotion {
                        proxy.scrollTo(index, anchor: .center)
                    } else {
                        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            }
        }
    }
}
