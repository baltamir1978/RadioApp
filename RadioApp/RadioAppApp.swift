//
//  RadioAppApp.swift
//  RadioApp
//
//  Created by Bruno Altamirano on 29/05/2026.
//

import Combine
import SwiftUI

@main
struct RadioAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { handleURL($0) }
                #if DEBUG
                // `-open <radioapp:// link>` at launch, as many times as needed: what a widget
                // does, for trying the app in the Simulator (`simctl openurl` asks first).
                .task {
                    let args = ProcessInfo.processInfo.arguments
                    for (i, arg) in args.enumerated() where arg == "-open" && args.indices.contains(i + 1) {
                        if let url = URL(string: args[i + 1]) { handleURL(url) }
                    }
                }
                #endif
        }
    }

    /// Handles the widgets' deep links: `radioapp://play?u=<streamURL>` starts a station and
    /// `radioapp://nowplaying` opens the player (with the lyrics) on what's playing.
    @MainActor
    private func handleURL(_ url: URL) {
        guard url.scheme == "radioapp" else { return }
        if url.host == "nowplaying", RadioPlayer.shared.currentStation != nil {
            AppNavigation.shared.showNowPlaying = true
            return
        }
        if url.host == "play",
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let stream = comps.queryItems?.first(where: { $0.name == "u" })?.value,
           let station = StationsStore.shared.stations.first(where: { $0.streamURL == stream }) {
            RadioPlayer.shared.play(station)
        }
    }
}

/// Screens that something outside the view asks to show — a widget's link, for one.
@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()
    @Published var showNowPlaying = false
}
