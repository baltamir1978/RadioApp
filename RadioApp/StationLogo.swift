import SwiftUI

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
    }

    private var fallbackView: some View {
        ZStack {
            fallbackColor
            Text(station.initials)
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // Deterministic color per station based on name hash
    private var fallbackColor: Color {
        let palette: [Color] = [
            Color(hex: "#FF6B35"),
            Color(hex: "#E8445A"),
            Color(hex: "#7C5CBF"),
            Color(hex: "#2D9CDB"),
            Color(hex: "#27AE8F"),
            Color(hex: "#219653"),
            Color(hex: "#F2994A"),
            Color(hex: "#EB5757"),
            Color(hex: "#56CCF2"),
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
}
