import SwiftUI

private let accent = Color.brand

// MARK: - Full-screen Now Playing

struct NowPlayingView: View {
    @EnvironmentObject var player: RadioPlayer
    @StateObject private var shazam = ShazamService()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Station logo
                if let station = player.currentStation {
                    StationLogo(station: station, size: 200)
                        .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
                        .padding(.bottom, 32)
                }

                // Now playing: song title (from stream metadata or Shazam) is the star
                // when known; otherwise the station name leads.
                VStack(spacing: 6) {
                    if let track = player.currentTrack, !track.isEmpty {
                        Text(track)
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        if let artist = player.currentArtist, !artist.isEmpty {
                            Text(artist)
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Text(player.currentStation?.name ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)

                        // Lyrics: links out to Apple Music in the published build; the
                        // personal fork (LYRICS_EMBEDDED) swaps in an in-app panel.
                        LyricsAccessory(
                            title: track,
                            artist: player.currentArtist,
                            appleMusicURL: shazam.match?.title == track ? shazam.match?.appleMusicURL : nil
                        )
                        .padding(.top, 10)
                    } else {
                        Text(player.currentStation?.name ?? "")
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
                .animation(.easeInOut(duration: 0.25), value: player.currentTrack)

                // Controls
                HStack(spacing: 52) {
                    // Stop
                    Button {
                        player.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.primary.opacity(0.6))
                            .frame(width: 52, height: 52)
                    }

                    // Play / Pause — main button
                    Button {
                        player.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(accent)
                                .frame(width: 76, height: 76)
                                .shadow(color: accent.opacity(0.45), radius: 14, y: 5)

                            if player.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white)
                                    .offset(x: player.isPlaying ? 0 : 2)
                            }
                        }
                    }

                    // Shazam
                    Button {
                        if !shazam.isListening { player.prepareForReidentify() }
                        shazam.identify()
                    } label: {
                        Image(systemName: shazam.isListening
                              ? "waveform.circle.fill"
                              : "waveform.and.magnifyingglass")
                            .font(.system(size: 22))
                            .foregroundStyle(shazam.isListening ? accent : .primary.opacity(0.6))
                            .frame(width: 52, height: 52)
                    }
                }
                .padding(.bottom, 40)

                // Shazam result
                if let result = shazam.match {
                    ShazamResultCard(match: result)
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Only surface the "no match" notice when we have nothing else to show —
                // if the station already provides the title, the error would be noise.
                if let err = shazam.errorMessage, (player.currentTrack ?? "").isEmpty {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [Color.mintSurface, Color.appBackground],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .animation(.spring(duration: 0.4), value: shazam.match != nil)
            .onChange(of: shazam.match?.title) { _, _ in
                if let m = shazam.match {
                    player.updateNowPlayingFromShazam(title: m.title, artist: m.artist, artworkURL: m.artworkURL)
                    if let station = player.currentStation {
                        HistoryStore.shared.addFromShazam(m, stationName: station.name)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.mintSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Live badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                        Text(NSLocalizedString("live", comment: "").uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                            .kerning(0.5)
                    }
                    .opacity(player.isPlaying ? 1 : 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Mini bar

struct NowPlayingBar: View {
    @EnvironmentObject var player: RadioPlayer
    @State private var showNowPlaying = false

    var body: some View {
        Button { showNowPlaying = true } label: {
            HStack(spacing: 12) {
                if let station = player.currentStation {
                    StationLogo(station: station, size: 42)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentStation?.name ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Group {
                        if let track = player.currentTrack {
                            Text(track).lineLimit(1)
                        } else {
                            Text(player.isLoading
                                 ? NSLocalizedString("loading", comment: "")
                                 : NSLocalizedString("live", comment: ""))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView().environmentObject(player)
        }
    }
}

// MARK: - Shazam result card

struct ShazamResultCard: View {
    let match: ShazamMatch

    var body: some View {
        HStack(spacing: 12) {
            if let url = match.artworkURL {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color(hex: "#F0F0F0")
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(match.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(match.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let url = match.appleMusicURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
