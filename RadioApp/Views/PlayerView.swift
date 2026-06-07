import SwiftUI

// MARK: - Station list

struct StationListView: View {
    @EnvironmentObject var player: RadioPlayer
    @EnvironmentObject var store: StationsStore
    @Binding var showSettings: Bool

    var body: some View {
        List(store.stations) { station in
            StationRow(station: station)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .onAppear {
                    if let idx = store.stations.firstIndex(of: station) {
                        let next = store.stations.indices.contains(idx + 1) ? store.stations[idx + 1] : nil
                        next.map { player.prefetch($0) }
                    }
                }
        }
        .listStyle(.plain)
        .padding(.bottom, player.currentStation != nil ? 110 : 0)
    }
}

// MARK: - Station row

struct StationRow: View {
    @EnvironmentObject var player: RadioPlayer
    let station: Station

    private var isActive: Bool { player.currentStation?.id == station.id }

    var body: some View {
        Button {
            if isActive { player.toggle() } else { player.play(station) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    StationLogoView(station: station, size: 48)
                    if isActive {
                        RoundedRectangle(cornerRadius: 48 * 0.22, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                        if player.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }

                Text(station.name)
                    .font(.body)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundColor(.primary)

                Spacer()

                if isActive && player.isPlaying {
                    AudioWaveIndicator()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Animated wave (playing indicator)

struct AudioWaveIndicator: View {
    @State private var animating = false

    private let heights: [CGFloat] = [10, 20, 14, 18, 8]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: animating ? h : 4)
                    .animation(
                        .easeInOut(duration: 0.4 + Double(i) * 0.08)
                            .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
        .frame(width: 22, height: 22)
        .onAppear { animating = true }
    }
}

// MARK: - Persistent player bar at bottom

struct PlayerBar: View {
    @EnvironmentObject var player: RadioPlayer
    @EnvironmentObject var shazam: ShazamService

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 10) {
                // Station + track info
                HStack(spacing: 12) {
                    if let station = player.currentStation {
                        StationLogoView(station: station, size: 40)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentStation?.name ?? "")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        // Stream metadata (ICY title)
                        if let track = player.metadata.streamTitle, !track.isEmpty {
                            Text(track)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .transition(.opacity)
                        } else {
                            Text("En directo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        player.toggle()
                    } label: {
                        ZStack {
                            if player.isLoading {
                                ProgressView().tint(.primary)
                            } else {
                                Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                                    .font(.system(size: 22))
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }

                // Shazam button (only while playing)
                if player.isPlaying {
                    HStack {
                        ShazamButton(shazam: shazam)
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .animation(.easeInOut(duration: 0.2), value: player.isPlaying)
    }
}
