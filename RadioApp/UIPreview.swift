import SwiftUI

#Preview("Station List") {
    NavigationStack {
        StationsListView(showSearch: .constant(false), showAdd: .constant(false), showHistory: .constant(false), showSettings: .constant(false))
    }
    .environmentObject(StationsStore())
    .environmentObject(RadioPlayer.shared)
    .tint(.brand)
}

#Preview("Now Playing") {
    NowPlayingView()
        .environmentObject(RadioPlayer.shared)
        .tint(.brand)
}
