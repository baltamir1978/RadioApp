import SwiftUI

struct StationsListView: View {
    @EnvironmentObject var store: StationsStore
    @EnvironmentObject var player: RadioPlayer
    @Binding var showSearch: Bool
    @Binding var showAdd: Bool
    @Binding var showHistory: Bool

    @State private var showNowPlaying = false
    @State private var stationToEdit: Station?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.stations) { station in
                    StationRow(station: station, onTap: {
                        player.play(station)
                        showNowPlaying = true
                    }, onEdit: {
                        stationToEdit = station
                    }, onDelete: {
                        if player.currentStation?.id == station.id { player.stop() }
                        store.remove(station)
                    })

                    if station.id != store.stations.last?.id {
                        Divider()
                            .padding(.leading, 82)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(NSLocalizedString("my_stations", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
                    .foregroundStyle(Color(hex: "#FF6B35"))
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showHistory = true } label: {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(Color(hex: "#FF6B35"))
                }
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color(hex: "#FF6B35"))
                }
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color(hex: "#FF6B35"))
                }
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environmentObject(player)
        }
        .sheet(item: $stationToEdit) { station in
            EditStationView(station: station)
                .environmentObject(store)
        }
        .overlay {
            if store.stations.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("no_stations", comment: ""),
                    systemImage: "radio",
                    description: Text(NSLocalizedString("add_stations_hint", comment: ""))
                )
            }
        }
    }
}

struct StationRow: View {
    @EnvironmentObject var player: RadioPlayer

    let station: Station
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var isActive: Bool {
        player.currentStation?.id == station.id
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                StationLogo(station: station, size: 56)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let country = station.country {
                            Text(country)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.35), in: Capsule())
                        }
                        if let genre = station.genre {
                            Text(genre)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if isActive {
                    LiveIndicator(isPlaying: player.isPlaying)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onTap() } label: {
                Label("Reproducir", systemImage: "play.fill")
            }
            Button { onEdit() } label: {
                Label("Editar", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
}

struct LiveIndicator: View {
    let isPlaying: Bool
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array([10, 16, 12, 8].enumerated()), id: \.offset) { i, maxH in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#FF6B35"))
                    .frame(width: 3, height: isPlaying ? (phase ? CGFloat(maxH) : CGFloat(8 + (i * 2))) : 5)
                    .animation(
                        isPlaying
                            ? .easeInOut(duration: 0.35 + Double(i) * 0.08).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.2),
                        value: phase
                    )
            }
        }
        .frame(width: 22, height: 20)
        .onAppear { phase = true }
        .onDisappear { phase = false }
    }
}
