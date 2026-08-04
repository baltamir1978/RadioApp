import SwiftUI
import UIKit

struct StationLogo: View {
    let station: Station
    let size: CGFloat

    var body: some View {
        Group {
            if let logoURL = station.logoURL, let url = URL(string: logoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .background(Color.white)
                    default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        // Decorative by default: the station name is always right next to it, so reading
        // the logo too would just repeat. Callers that show it alone re-label it.
        .accessibilityHidden(true)
    }

    private var fallbackView: some View {
        ZStack {
            fallbackColor
            Text(station.initials)
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // Deterministic color per station based on name hash.
    // Every entry carries white initials, so each one clears 3:1 against white — the four
    // brightest of the original palette (orange, teal, amber, sky) sat between 1.9:1 and
    // 2.8:1 and were darkened to the same hue.
    private var fallbackColor: Color {
        let palette: [Color] = [
            Color(hex: "#D9541F"),
            Color(hex: "#E8445A"),
            Color(hex: "#7C5CBF"),
            Color(hex: "#2D9CDB"),
            Color(hex: "#1E8A72"),
            Color(hex: "#219653"),
            Color(hex: "#C97A22"),
            Color(hex: "#EB5757"),
            Color(hex: "#1B8FBF"),
            Color(hex: "#9B51E0"),
        ]
        let index = abs(station.name.hashValue) % palette.count
        return palette[index]
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Builds a color that resolves to a different value in light vs. dark mode.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
