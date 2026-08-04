import SwiftUI
import UIKit

extension Color {
    init(hexW: String) {
        let hex = hexW.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Resolves to a different value in light vs. dark mode. Mirrors the app's
    /// `Color(light:dark:)`, duplicated because the extension has its own module.
    init(lightW: String, darkW: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hexW: traits.userInterfaceStyle == .dark ? darkW : lightW))
        })
    }

    /// Mint/teal palette mirroring the app theme — including its dark variants, so a widget
    /// on a dark home screen doesn't stay a bright mint card. Same AA-checked values as
    /// `Theme.swift`; keep the two in step.
    static let wBrand = Color(lightW: "#1F6F64", darkW: "#5FD3C2")
    static let wBackground = Color(lightW: "#EAF7F3", darkW: "#0E1B19")
    static let wSurface = Color(lightW: "#D6EFE8", darkW: "#16302C")
}

/// Builds the `radioapp://play?u=<streamURL>` deep link used by widget buttons.
func playDeepLink(streamURL: String) -> URL? {
    var comps = URLComponents()
    comps.scheme = "radioapp"
    comps.host = "play"
    comps.queryItems = [URLQueryItem(name: "u", value: streamURL)]
    return comps.url
}
