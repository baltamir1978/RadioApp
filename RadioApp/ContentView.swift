import SwiftUI

struct ContentView: View {
    @StateObject private var store = StationsStore.shared
    @StateObject private var player = RadioPlayer.shared

    @State private var showSearch = false
    @State private var showAdd = false
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StationsListView(showSearch: $showSearch, showAdd: $showAdd, showHistory: $showHistory, showSettings: $showSettings)
                    .environmentObject(store)
                    .environmentObject(player)

                if player.currentStation != nil {
                    NowPlayingBar()
                        .environmentObject(player)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: player.currentStation != nil)
            .background(Color.appBackground.ignoresSafeArea())
        }
        .tint(.brand)
        // Auto-save the live (ICY) track to history whenever it changes.
        .onChange(of: player.currentTrack) { _, track in
            if let track, let station = player.currentStation {
                HistoryStore.shared.addFromICY(track: track, artist: player.currentArtist, stationName: station.name)
            }
        }
        .sheet(isPresented: $showSearch) {
            StationSearchView()
                .environmentObject(store)
                .environmentObject(player)
                .tint(.brand)
        }
        .sheet(isPresented: $showAdd) {
            AddStationView()
                .environmentObject(store)
                .tint(.brand)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

#Preview {
    ContentView()
}
