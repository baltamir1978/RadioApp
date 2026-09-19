import Foundation
import os

private nonisolated let lyricsLog = Logger(subsystem: "com.radioapp.playback", category: "lyrics")

/// Song lyrics from LRCLIB (lrclib.net): free, keyless, and — what matters for the widget —
/// usually time-stamped line by line, so the widget can follow the song.
nonisolated enum LyricsService {
    enum Outcome: Sendable {
        case found(SongLyrics)
        case notFound
        /// The network failed; worth asking again later, unlike `notFound`.
        case failed
    }

    /// Looks the song up as given and, if that finds nothing, with title and artist swapped:
    /// some stations send "Title - Artist", and until the cover lookup has set the order right
    /// the two can't be told apart. Then collaborations: LRCLIB files "El Canto del Loco y Amaia
    /// Montero" under the first name, or under both spelt otherwise, so the first name alone and
    /// finally the title alone are tried — the latter only taking a hit by one of the artists.
    static func lookup(track: String, artist: String?) async -> Outcome {
        let outcome = await search(track: track, artist: artist)
        guard case .notFound = outcome, let artist, !artist.isEmpty else { return outcome }
        let swapped = await search(track: artist, artist: track)
        guard case .notFound = swapped else { return swapped }
        let names = artistNames(artist)
        if names.count > 1 {
            let main = await search(track: track, artist: names[0], byAnyOf: names)
            guard case .notFound = main else { return main }
        }
        return await search(track: track, artist: nil, byAnyOf: names)
    }

    /// "A y B", "A & B", "A feat. B", "A, B", "A x B" → ["A", "B"].
    static func artistNames(_ artist: String) -> [String] {
        let separator = #"\s*(?:,|&|\+|/|\b(?:y|and|con|with|x|vs|feat|ft|featuring)\b\.?)\s*"#
        return artist.replacingOccurrences(of: separator, with: "\u{1F}", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `byAnyOf`: searching by title alone, a hit counts only if it's by one of these artists.
    private static func search(track: String, artist: String?, byAnyOf names: [String] = []) async -> Outcome {
        guard var comps = URLComponents(string: "https://lrclib.net/api/search") else { return .notFound }
        let title = stripDecorations(track).trimmingCharacters(in: .whitespaces)
        var query = [URLQueryItem(name: "track_name", value: title.isEmpty ? track : title)]
        if let artist, !artist.isEmpty { query.append(URLQueryItem(name: "artist_name", value: artist)) }
        comps.queryItems = query
        guard let url = comps.url else { return .notFound }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        // LRCLIB asks clients to identify themselves.
        request.setValue("RadioApp/1.0 (https://github.com/baltamir1978/RadioApp)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return .failed }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            lyricsLog.error("LRCLIB returned \(http.statusCode, privacy: .public)")
            return .failed
        }
        guard let hits = try? JSONDecoder().decode([Hit].self, from: data) else { return .failed }
        guard let best = pick(from: hits, track: track, byAnyOf: names) else { return .notFound }

        if best.instrumental == true {
            return .found(SongLyrics(synced: [], plain: [], isInstrumental: true, duration: best.duration))
        }
        let synced = best.syncedLyrics.map(parseLRC) ?? []
        let plain = (best.plainLyrics ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let lyrics = SongLyrics(synced: synced, plain: trimBlankEdges(plain), isInstrumental: false,
                                duration: best.duration)
        return lyrics.isEmpty ? .notFound : .found(lyrics)
    }

    /// Prefers an entry with synced lyrics whose title really matches. Radio metadata is often
    /// sloppy ("Artist - Title (Radio Edit)"), so the search is loose and the match here is
    /// what keeps a random song's lyrics off the screen. Very short durations are junk uploads.
    private static func pick(from hits: [Hit], track: String, byAnyOf names: [String]) -> Hit? {
        let wanted = normalize(stripDecorations(track))
        let artists = names.map(normalize).filter { !$0.isEmpty }
        let plausible = hits.filter { hit in
            guard (hit.duration ?? 120) > 45 else { return false }
            if !artists.isEmpty {
                let by = normalize(hit.artistName ?? "")
                guard !by.isEmpty, artists.contains(where: { by.contains($0) || $0.contains(by) }) else { return false }
            }
            let title = normalize(stripDecorations(hit.trackName ?? ""))
            return !title.isEmpty && (title.contains(wanted) || wanted.contains(title))
        }
        return plausible.first { $0.syncedLyrics?.isEmpty == false }
            ?? plausible.first { $0.plainLyrics?.isEmpty == false || $0.instrumental == true }
    }

    /// Parses `[mm:ss.xx] text` lines. Lines with several stamps (a repeated chorus written
    /// once) produce one entry per stamp.
    static func parseLRC(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var stamps: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let seconds = parseStamp(tag) { stamps.append(seconds) }
                rest = rest[rest.index(after: close)...]
            }
            let body = rest.trimmingCharacters(in: .whitespaces)
            lines += stamps.map { LyricLine(time: $0, text: body) }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private static func parseStamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }

    private static func trimBlankEdges(_ lines: [String]) -> [String] {
        var lines = lines
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    /// Drops "(Radio Edit)", "[Remastered]" and "feat." tails that the lyrics database won't have.
    private static func stripDecorations(_ s: String) -> String {
        var out = s
        for opener in ["(", "["] {
            if let i = out.firstIndex(of: Character(opener)), i != out.startIndex { out = String(out[..<i]) }
        }
        for marker in [" feat.", " ft.", " featuring "] {
            if let r = out.range(of: marker, options: .caseInsensitive) { out = String(out[..<r.lowerBound]) }
        }
        return out
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private struct Hit: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }
}
