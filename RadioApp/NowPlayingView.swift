import SwiftUI

private let accent = Color.brand

// MARK: - Full-screen Now Playing

struct NowPlayingView: View {
    @EnvironmentObject var player: RadioPlayer
    @StateObject private var shazam = ShazamService()
    @Environment(\.dismiss) private var dismiss

    private var stationName: String { player.currentStation?.name ?? "" }

    /// What the cover art stands for: the song when we know it, else the station.
    private var heroLabel: String {
        if let track = player.currentTrack, !track.isEmpty {
            return String(format: NSLocalizedString("a11y_artwork", comment: ""), track)
        }
        return String(format: NSLocalizedString("a11y_station_logo", comment: ""), stationName)
    }

    private var playPauseLabel: String {
        if player.isReconnecting { return NSLocalizedString("reconnecting", comment: "") }
        if player.isLoading { return NSLocalizedString("loading", comment: "") }
        return NSLocalizedString(player.isPlaying ? "pause" : "play", comment: "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Hero: the recognized song's cover when we have one, otherwise the station
                // logo. Cross-fades as songs change on a continuous broadcast.
                Group {
                    if let art = player.currentArtworkURL {
                        AsyncImage(url: art) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else if let station = player.currentStation {
                                StationLogo(station: station, size: 200)
                            } else {
                                Color.mintSurface
                            }
                        }
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    } else if let station = player.currentStation {
                        StationLogo(station: station, size: 200)
                    }
                }
                .id(player.currentArtworkURL)
                .transition(.opacity)
                .frame(width: 200, height: 200)
                .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
                .padding(.bottom, 32)
                .animation(.easeInOut(duration: 0.35), value: player.currentArtworkURL)
                // The hero is the one image worth announcing: it's the cover of what's on.
                .accessibilityElement()
                .accessibilityLabel(heroLabel)

                // Now playing: song title (from stream metadata or Shazam) is the star
                // when known; otherwise the station name leads.
                VStack(spacing: 6) {
                    if let track = player.currentTrack, !track.isEmpty {
                        Text(track)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        if let artist = player.currentArtist, !artist.isEmpty {
                            Text(artist)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        // Keep the station's identity present even when the cover art has
                        // taken over the hero: a small logo + name chip under the song.
                        HStack(spacing: 6) {
                            if let station = player.currentStation {
                                StationLogo(station: station, size: 18)
                            }
                            Text(player.currentStation?.name ?? "")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 2)
                        .accessibilityElement(children: .combine)

                        // Lyrics: links out to Apple Music in the published build; the
                        // personal fork (LYRICS_EMBEDDED) swaps in an in-app panel.
                        LyricsAccessory(
                            title: track,
                            artist: player.currentArtist,
                            appleMusicURL: player.currentAppleMusicURL
                        )
                        .padding(.top, 10)
                    } else {
                        Text(player.currentStation?.name ?? "")
                            .font(.title2.weight(.bold))
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
                            .font(.title2)
                            .foregroundStyle(.primary.opacity(0.6))
                            .frame(width: 52, height: 52)
                    }
                    .accessibilityLabel(NSLocalizedString("a11y_stop", comment: ""))

                    // Play / Pause — main button
                    Button {
                        player.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(accent)
                                .frame(width: 76, height: 76)
                                .shadow(color: accent.opacity(0.45), radius: 14, y: 5)

                            // Not plain white: in dark mode the accent is a light mint, and
                            // white on it sits at 1.8:1. The screen background inverts with
                            // the accent, so the glyph stays above 5:1 in both modes.
                            if player.isLoading || player.isReconnecting {
                                ProgressView().tint(Color.appBackground)
                            } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.appBackground)
                                    .offset(x: player.isPlaying ? 0 : 2)
                            }
                        }
                    }
                    .accessibilityLabel(playPauseLabel)

                    // Shazam
                    Button {
                        if !shazam.isListening { player.prepareForReidentify() }
                        shazam.identify()
                    } label: {
                        Image(systemName: shazam.isListening
                              ? "waveform.circle.fill"
                              : "waveform.and.magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(shazam.isListening ? accent : .primary.opacity(0.6))
                            .frame(width: 52, height: 52)
                    }
                    .accessibilityLabel(NSLocalizedString("identify_song", comment: ""))
                    .accessibilityAddTraits(shazam.isListening ? .isSelected : [])
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
                        // Speak the failure as soon as it appears — the user is waiting on it.
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityRespondsToUserInteraction(false)
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
                    player.updateNowPlayingFromShazam(title: m.title, artist: m.artist, artworkURL: m.artworkURL, appleMusicURL: m.appleMusicURL)
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
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent)
                            .kerning(0.5)
                    }
                    .opacity(player.isPlaying ? 1 : 0)
                    // Faded out is invisible, not merely dim — keep it out of the rotor too.
                    .accessibilityHidden(!player.isPlaying)
                    .accessibilityElement()
                    .accessibilityLabel(NSLocalizedString("live", comment: ""))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(NSLocalizedString("a11y_collapse_player", comment: ""))
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
        HStack(spacing: 12) {
            // Everything left of the play button opens the full player. Keeping it as its
            // own button (instead of wrapping the row) stops VoiceOver from nesting the
            // play control inside a larger tappable element.
            Button { showNowPlaying = true } label: {
                HStack(spacing: 12) {
                    if let station = player.currentStation {
                        StationLogo(station: station, size: 42)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentStation?.name ?? "")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Group {
                            if let track = player.currentTrack {
                                Text(track).lineLimit(1)
                            } else {
                                Text(player.isReconnecting
                                     ? NSLocalizedString("reconnecting", comment: "")
                                     : player.isLoading
                                     ? NSLocalizedString("loading", comment: "")
                                     : NSLocalizedString("live", comment: ""))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(NSLocalizedString("a11y_open_player", comment: ""))

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString(player.isPlaying ? "pause" : "play", comment: ""))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
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
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(match.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            if let url = match.appleMusicURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(accent)
                }
                .accessibilityLabel(NSLocalizedString("a11y_open_apple_music", comment: ""))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
