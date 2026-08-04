import SwiftUI

struct StationsListView: View {
    @EnvironmentObject var store: StationsStore
    @EnvironmentObject var player: RadioPlayer
    @Binding var showSearch: Bool
    @Binding var showAdd: Bool
    @Binding var showHistory: Bool
    @Binding var showSettings: Bool

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
        .toolbarBackground(Color.mintSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.brand)
                }
                EditButton()
                    .foregroundStyle(Color.brand)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showHistory = true } label: {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(Color.brand)
                }
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.brand)
                }
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.brand)
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
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let country = station.country {
                            // White on a 35%-alpha grey landed at 1.5:1 over the mint
                            // background. Primary text on the same tint reads cleanly in
                            // both appearances, and matches the search results row.
                            Text(country)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.25), in: Capsule())
                        }
                        if let genre = station.genre {
                            Text(genre)
                                .font(.footnote)
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
        // One VoiceOver stop per station: name, then country/genre, then whether it's live.
        .accessibilityElement(children: .combine)
        .accessibilityHint(NSLocalizedString("a11y_station_hint", comment: ""))
        .accessibilityAddTraits(isActive && player.isPlaying ? [.isButton, .startsMediaSession] : .isButton)
        .contextMenu {
            Button { onTap() } label: {
                Label(NSLocalizedString("play", comment: ""), systemImage: "play.fill")
            }
            Button { onEdit() } label: {
                Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
            }
        }
    }
}

struct LiveIndicator: View {
    let isPlaying: Bool
    @State private var phase = false
    /// The bars loop forever, so honour the system setting that asks motion to stop.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animating: Bool { isPlaying && !reduceMotion }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array([10, 16, 12, 8].enumerated()), id: \.offset) { i, maxH in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.brand)
                    .frame(width: 3, height: barHeight(index: i, maxH: maxH))
                    .animation(
                        animating
                            ? .easeInOut(duration: 0.35 + Double(i) * 0.08).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.2),
                        value: phase
                    )
            }
        }
        .frame(width: 22, height: 20)
        .onAppear { phase = true }
        .onDisappear { phase = false }
        // Purely visual, but it carries real state — say it rather than hide it.
        .accessibilityElement()
        .accessibilityLabel(isPlaying
                            ? NSLocalizedString("a11y_playing_now", comment: "")
                            : NSLocalizedString("paused", comment: ""))
    }

    private func barHeight(index: Int, maxH: Int) -> CGFloat {
        guard isPlaying else { return 5 }
        // With motion reduced the bars hold a static staggered shape instead of pulsing.
        guard animating else { return CGFloat(8 + (index * 2)) }
        return phase ? CGFloat(maxH) : CGFloat(8 + (index * 2))
    }
}
