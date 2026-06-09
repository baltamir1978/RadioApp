import SwiftUI

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

    /// Mint/teal palette mirroring the app theme.
    static let wBrand = Color(hexW: "#2E9E8F")
    static let wBackground = Color(hexW: "#EAF7F3")
    static let wSurface = Color(hexW: "#D6EFE8")
}

/// Builds the `radioapp://play?u=<streamURL>` deep link used by widget buttons.
func playDeepLink(streamURL: String) -> URL? {
    var comps = URLComponents()
    comps.scheme = "radioapp"
    comps.host = "play"
    comps.queryItems = [URLQueryItem(name: "u", value: streamURL)]
    return comps.url
}
