import SwiftUI

/// Lyrics support, split by build so the published app stays clear of lyrics licensing.
///
/// Lyrics are copyrighted by music publishers; showing them in a published app needs a
/// licence (or a licensed provider). So:
///
/// - **Published build (default):** `LyricsAccessory` renders a "View lyrics" button that
///   opens Apple Music / Safari. We never store or display the lyric text ourselves — we
///   only link out — which keeps the App Store build clean.
///
/// - **Personal fork:** define the `LYRICS_EMBEDDED` compilation condition to compile in
///   an in-app panel backed by LRCLIB. That code lives entirely behind `#if LYRICS_EMBEDDED`,
///   so it is **not even compiled** into the published binary.

// MARK: - Link-out (published build)

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

// MARK: - Accessory shown on the Now Playing screen

struct LyricsAccessory: View {
    let title: String
    var artist: String? = nil
    /// Shazam's exact Apple Music URL when the track was identified; nil for ICY-only tracks.
    var appleMusicURL: URL? = nil

    var body: some View {
        #if LYRICS_EMBEDDED
        LyricsPanel(title: title, artist: artist)
        #else
        if let url = LyricsLink.appleMusicURL(title: title, artist: artist, exact: appleMusicURL) {
            Link(destination: url) {
                Label(NSLocalizedString("view_lyrics", comment: ""), systemImage: "quote.bubble")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brand)
        }
        #endif
    }
}

// MARK: - Embedded panel (personal fork only — never compiled into the App Store build)

#if LYRICS_EMBEDDED
/// Starter in-app lyrics panel for the personal fork. Fetches plain (and, when available,
/// time-synced) lyrics from LRCLIB. This is a starting point — refine the UI as you like.
///
/// Possible next step: feed ShazamKit's `matchOffset` in to highlight synced lines live.
struct LyricsPanel: View {
    let title: String
    let artist: String?

    @State private var lyrics: String?
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if let lyrics, !lyrics.isEmpty {
                ScrollView {
                    Text(lyrics)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
            } else if failed {
                Text(NSLocalizedString("lyrics_unavailable", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(artist ?? "")-\(title)") { await load() }
    }

    private func load() async {
        loading = true; failed = false; lyrics = nil
        defer { loading = false }
        do {
            lyrics = try await LRCLibClient.plainLyrics(title: title, artist: artist)
            failed = (lyrics?.isEmpty ?? true)
        } catch {
            failed = true
        }
    }
}

/// Minimal LRCLIB client. Free, community-sourced, no API key. https://lrclib.net/docs
enum LRCLibClient {
    private struct Hit: Decodable {
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static func plainLyrics(title: String, artist: String?) async throws -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist ?? "")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("RadioApp (personal)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let hits = try JSONDecoder().decode([Hit].self, from: data)
        return hits.first(where: { !($0.plainLyrics?.isEmpty ?? true) })?.plainLyrics
    }
}
#endif
