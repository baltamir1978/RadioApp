import SwiftUI

private let accent = Color(hex: "#FF6B35")

struct HistoryView: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var store = StationsStore.shared
    @ObservedObject private var player = RadioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false

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
            .navigationTitle(NSLocalizedString("history_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("close", comment: "")) { dismiss() }
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
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { songs[$0].id })
                        history.delete(at: IndexSet(
                            history.songs.indices.filter { ids.contains(history.songs[$0].id) }
                        ))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
                    Image(systemName: song.source == .shazam ? "shazam.logo" : "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(song.source == .shazam ? accent : .secondary)
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
