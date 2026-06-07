import SwiftUI

/// Shows the station logo from URL, falling back to colored initials.
struct StationLogoView: View {
    let station: Station
    var size: CGFloat = 44

    private var initialsColor: Color {
        // Deterministic color from station name
        let colors: [Color] = [.red, .orange, .blue, .purple, .green, .pink, .indigo, .teal]
        let index = abs(station.name.hashValue) % colors.count
        return colors[index]
    }

    var body: some View {
        Group {
            if let rawURL = station.logoURL, let url = URL(string: rawURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var initialsView: some View {
        ZStack {
            initialsColor
                .opacity(0.18)
            Text(station.initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundColor(initialsColor)
        }
    }
}
