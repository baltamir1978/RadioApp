import SwiftUI

struct ContentView: View {
    @StateObject private var store = StationsStore()
    @StateObject private var player = RadioPlayer.shared

    @State private var showSearch = false
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StationsListView(showSearch: $showSearch, showAdd: $showAdd)
                    .environmentObject(store)
                    .environmentObject(player)

                if player.currentStation != nil {
                    NowPlayingBar()
                        .environmentObject(player)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: player.currentStation != nil)
        }
        .tint(Color(hex: "#FF6B35"))
        .sheet(isPresented: $showSearch) {
            StationSearchView()
                .environmentObject(store)
                .environmentObject(player)
                .tint(Color(hex: "#FF6B35"))
        }
        .sheet(isPresented: $showAdd) {
            AddStationView()
                .environmentObject(store)
                .tint(Color(hex: "#FF6B35"))
        }
    }
}

#Preview {
    ContentView()
}
