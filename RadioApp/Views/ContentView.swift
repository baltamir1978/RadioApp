import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: RadioPlayer
    @EnvironmentObject var store: StationsStore
    @EnvironmentObject var history: HistoryStore
    @State private var showSettings = false
    @State private var showHistory  = false
    @State private var showSearch   = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                StationListView(showSettings: $showSettings)
                if player.currentStation != nil {
                    PlayerBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(String(localized: "app.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        // History
                        Button { showHistory = true } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "music.note.list")
                                if !history.songs.isEmpty {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                        // Search
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showHistory)  { HistoryView() }
            .sheet(isPresented: $showSearch)   { StationSearchView() }
            .animation(.easeInOut(duration: 0.25), value: player.currentStation != nil)
        }
    }
}
