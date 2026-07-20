import SwiftUI

private let accent = Color.brand

struct HistoryView: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var store = StationsStore.shared
    @ObservedObject private var player = RadioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false
    @State private var showIgnored = false

    private var grouped: [(String, [ListenedSong])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .current
        var result: [(String, [ListenedSong])] = []
        var seen: [String: Int] = [:]
        for song in history.songs {
            let key = formatter.string(from: song.listenedAt)
            if let idx = seen[key] {
                result[idx].1.append(song)
            } else {
                seen[key] = result.count
                result.append((key, [song]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if history.songs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("history_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.mintSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("close", comment: "")) { dismiss() }
                }
                if !history.ignored.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showIgnored = true
                        } label: {
                            Image(systemName: "nosign")
                        }
                        .accessibilityLabel(NSLocalizedString("ignored_title", comment: ""))
                    }
                }
                if !history.songs.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Text(NSLocalizedString("history_clear_all", comment: ""))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showIgnored) { IgnoredListView() }
            .confirmationDialog(NSLocalizedString("history_clear_confirm", comment: ""),
                                isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button(NSLocalizedString("history_clear_all", comment: ""), role: .destructive) { history.clearAll() }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            }
        }
        .tint(accent)
    }

    private var songList: some View {
        List {
            ForEach(grouped, id: \.0) { (day, songs) in
                Section(day) {
                    ForEach(songs) { song in
                        SongHistoryRow(song: song) { playStation(named: $0) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    history.delete(song)
                                } label: {
                                    Label(NSLocalizedString("history_delete", comment: ""),
                                          systemImage: "trash")
                                }
                                // "Delete for good" only makes sense for auto-captured tracks.
                                if song.source == .icy && !song.favorite {
                                    Button {
                                        history.ignoreAndPurge(song)
                                    } label: {
                                        Label(NSLocalizedString("history_ignore", comment: ""),
                                              systemImage: "nosign")
                                    }
                                    .tint(.orange)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(NSLocalizedString("history_empty", comment: ""), systemImage: "music.note.list")
        } description: {
            Text(NSLocalizedString("history_empty_detail", comment: ""))
        }
    }

    private func playStation(named name: String) {
        if let station = store.stations.first(where: { $0.name == name }) {
            player.play(station)
            dismiss()
        }
    }
}

// MARK: - Row

struct SongHistoryRow: View {
    let song: ListenedSong
    let onPlayStation: (String) -> Void

    private var timeString: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: song.listenedAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(song.isHighlighted ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: "radio").font(.caption2)
                    Text(song.stationName).font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(timeString).font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if song.source == .shazam {
                        Image(systemName: "shazam.logo")
                            .font(.callout)
                            .foregroundStyle(accent)
                    } else {
                        // Heart to explicitly keep an auto-captured track.
                        Button {
                            HistoryStore.shared.toggleFavorite(song)
                        } label: {
                            Image(systemName: song.favorite ? "heart.fill" : "heart")
                                .font(.callout)
                                .foregroundStyle(song.favorite ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                        }
                        .buttonStyle(.plain)
                    }
                    if let raw = song.appleMusicURL, let url = URL(string: raw) {
                        Link(destination: url) {
                            Image(systemName: "music.note").font(.caption2).foregroundStyle(.pink)
                        }
                    }
                    Button {
                        onPlayStation(song.stationName)
                    } label: {
                        Image(systemName: "play.circle").font(.callout).foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var artwork: some View {
        if let raw = song.artworkURL, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { artworkPlaceholder }
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Color(.secondarySystemFill)
            Image(systemName: "music.note").font(.system(size: 18)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Ignored titles

/// Lets the user review and undo the per-station titles they chose to ignore.
struct IgnoredListView: View {
    @ObservedObject private var history = HistoryStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if history.ignored.isEmpty {
                    ContentUnavailableView {
                        Label(NSLocalizedString("ignored_empty", comment: ""), systemImage: "nosign")
                    } description: {
                        Text(NSLocalizedString("ignored_empty_detail", comment: ""))
                    }
                } else {
                    List {
                        Section {
                            ForEach(history.ignored) { entry in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Image(systemName: "radio").font(.caption2)
                                        Text(entry.stationName).font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        history.unignore(entry)
                                    } label: {
                                        Label(NSLocalizedString("ignored_restore", comment: ""),
                                              systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(accent)
                                }
                            }
                        } footer: {
                            Text(NSLocalizedString("ignored_footer", comment: ""))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("ignored_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.mintSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("close", comment: "")) { dismiss() }
                }
            }
        }
        .tint(accent)
    }
}
