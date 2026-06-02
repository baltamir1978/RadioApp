import Foundation

/// Provides access to the shared player and store for CarPlay.
@MainActor
class CarPlayBridge {
    static let shared = CarPlayBridge()

    let player = RadioPlayer.shared
    let store = StationsStore()

    private init() {}
}
