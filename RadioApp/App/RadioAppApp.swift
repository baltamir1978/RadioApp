import SwiftUI
import Combine

@main
struct RadioAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var player  = RadioPlayer()
    @StateObject private var store   = StationsStore()
    @StateObject private var shazam  = ShazamService()
    @StateObject private var history = HistoryStore()

    @State private var cancellables = Set<AnyCancellable>()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(store)
                .environmentObject(shazam)
                .environmentObject(history)
                .onAppear { wireHistorySaving() }
        }
    }

    /// Subscribe to ICY metadata changes and save new tracks automatically.
    private func wireHistorySaving() {
        player.newICYTrackPublisher
            .sink { station, rawTitle in
                history.addFromICY(raw: rawTitle, station: station)
            }
            .store(in: &cancellables)
    }
}
