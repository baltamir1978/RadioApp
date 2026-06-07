import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var player: RadioPlayer
    @EnvironmentObject var store: StationsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false

    private var grouped: [(String, [ListenedSong])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "es_ES")
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
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                if !history.songs.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Text("Borrar todo")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .confirmationDialog("¿Borrar todo el historial?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Borrar todo", role: .destructive) { history.clearAll() }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    // MARK: - List

    private var songList: some View {
        List {
            ForEach(grouped, id: \.0) { (day, songs) in
                Section(day) {
                    ForEach(songs) { song in
                        SongHistoryRow(song: song, onPlayStation: playStation(named:))
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

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text("Sin historial todavía")
                .font(.headline)
            Text("Las canciones que escuches aparecerán aquí automáticamente o al identificarlas con Shazam.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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
            // Artwork or placeholder
            Group {
                if let raw = song.artworkURL, let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            artworkPlaceholder
                        }
                    }
                } else {
                    artworkPlaceholder
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Titles
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: "radio")
                        .font(.caption2)
                    Text(song.stationName)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    // Source badge
                    Image(systemName: song.source == .shazam ? "shazam.logo" : "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundColor(song.source == .shazam ? .accentColor : .secondary)

                    // Apple Music link
                    if let raw = song.appleMusicURL, let url = URL(string: raw) {
                        Link(destination: url) {
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundColor(.pink)
                        }
                    }

                    // Jump to station
                    Button {
                        onPlayStation(song.stationName)
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Color(.secondarySystemFill)
            Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
        }
    }
}
