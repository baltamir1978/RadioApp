//
//  RadioAppApp.swift
//  RadioApp
//
//  Created by Bruno Altamirano on 29/05/2026.
//

import SwiftUI

@main
struct RadioAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { handleURL($0) }
        }
    }

    /// Handles `radioapp://play?u=<streamURL>` deep links from the widget.
    @MainActor
    private func handleURL(_ url: URL) {
        guard url.scheme == "radioapp" else { return }
        if url.host == "play",
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let stream = comps.queryItems?.first(where: { $0.name == "u" })?.value,
           let station = StationsStore.shared.stations.first(where: { $0.streamURL == stream }) {
            RadioPlayer.shared.play(station)
        }
    }
}
