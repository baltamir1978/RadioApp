import SwiftUI

struct AppIconView: View {
    var size: CGFloat = 1024

    private var s: CGFloat { size / 1024 }

    var body: some View {
        ZStack {
            // Solid fill for the full square — iOS applies its own rounded corner mask
            Rectangle()
                .fill(Color(hex: "#FFF3E0"))

            // Background – warm cream gradient (Liquid Glass compatible: light + colorful)
            RoundedRectangle(cornerRadius: 220 * s)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#FFF3E0"), Color(hex: "#FFD59E"), Color(hex: "#FFAB61")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            // Subtle warm noise / texture layer
            RoundedRectangle(cornerRadius: 220 * s)
                .fill(Color(hex: "#FF8C42").opacity(0.08))

            // Outer body – bold warm brown, solid filled
            RoundedRectangle(cornerRadius: 160 * s)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#A0522D"), Color(hex: "#6B3A1F")],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 860 * s, height: 680 * s)
                .shadow(color: Color(hex: "#6B3A1F").opacity(0.35), radius: 30 * s, y: 14 * s)

            // Thin highlight rim
            RoundedRectangle(cornerRadius: 160 * s)
                .stroke(Color(hex: "#D4855A").opacity(0.5), lineWidth: 2.5 * s)
                .frame(width: 860 * s, height: 680 * s)

            // Top band
            RoundedRectangle(cornerRadius: 16 * s)
                .fill(Color(hex: "#4A2209").opacity(0.55))
                .frame(width: 780 * s, height: 58 * s)
                .offset(y: -250 * s)

            // Frequency scale labels
            HStack(spacing: 38 * s) {
                ForEach(["88", "92", "96", "100", "104", "108"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 22 * s, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#F5DEB3").opacity(0.6))
                }
            }
            .offset(y: -250 * s)

            // Frequency needle
            Rectangle()
                .fill(Color(hex: "#FF6B35"))
                .frame(width: 3 * s, height: 55 * s)
                .offset(x: 30 * s, y: -250 * s)

            // Speaker grille – left oval
            ZStack {
                Ellipse()
                    .fill(Color(hex: "#2A1206"))
                    .frame(width: 320 * s, height: 260 * s)

                Ellipse()
                    .stroke(Color(hex: "#C8733A").opacity(0.5), lineWidth: 4 * s)
                    .frame(width: 320 * s, height: 260 * s)

                // Grille dots
                VStack(spacing: 18 * s) {
                    ForEach(0..<7) { row in
                        HStack(spacing: 16 * s) {
                            ForEach(0..<10) { col in
                                Circle()
                                    .fill(Color(hex: "#6B3A1F").opacity(0.9))
                                    .frame(width: 8 * s, height: 8 * s)
                            }
                        }
                    }
                }
                .frame(width: 290 * s, height: 230 * s)
                .clipShape(Ellipse().scale(0.88))
            }
            .offset(x: -200 * s, y: 20 * s)

            // Right panel – controls
            VStack(spacing: 28 * s) {
                // Main tuning knob
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "#D4A017"), Color(hex: "#8B6914")],
                                center: UnitPoint(x: 0.35, y: 0.35),
                                startRadius: 0,
                                endRadius: 80 * s
                            )
                        )
                        .frame(width: 160 * s, height: 160 * s)
                        .shadow(color: .black.opacity(0.5), radius: 12 * s, y: 6 * s)

                    Circle()
                        .stroke(Color(hex: "#F5C842").opacity(0.4), lineWidth: 3 * s)
                        .frame(width: 160 * s, height: 160 * s)

                    // Knob tick marks
                    ForEach(0..<12) { i in
                        Rectangle()
                            .fill(Color(hex: "#2C1810").opacity(0.6))
                            .frame(width: 2 * s, height: 12 * s)
                            .offset(y: -65 * s)
                            .rotationEffect(.degrees(Double(i) * 30))
                    }

                    // Center dot
                    Circle()
                        .fill(Color(hex: "#1A0E08"))
                        .frame(width: 20 * s, height: 20 * s)

                    // Indicator line
                    Rectangle()
                        .fill(Color(hex: "#FF6B35"))
                        .frame(width: 4 * s, height: 50 * s)
                        .offset(y: -42 * s)
                        .rotationEffect(.degrees(-40))
                }

                // Two small knobs
                HStack(spacing: 30 * s) {
                    ForEach(0..<2) { _ in
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color(hex: "#A0522D"), Color(hex: "#5C2E0A")],
                                        center: UnitPoint(x: 0.35, y: 0.35),
                                        startRadius: 0,
                                        endRadius: 40 * s
                                    )
                                )
                                .frame(width: 70 * s, height: 70 * s)
                                .shadow(color: .black.opacity(0.4), radius: 6 * s, y: 3 * s)

                            Rectangle()
                                .fill(Color(hex: "#FF6B35").opacity(0.8))
                                .frame(width: 3 * s, height: 22 * s)
                                .offset(y: -18 * s)
                                .rotationEffect(.degrees(30))
                        }
                    }
                }
            }
            .offset(x: 170 * s, y: 20 * s)

            // Antenna
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#C0C0C0"), Color(hex: "#808080")],
                        startPoint: .bottom, endPoint: .top
                    )
                )
                .frame(width: 8 * s, height: 200 * s)
                .rotationEffect(.degrees(-15))
                .offset(x: 260 * s, y: -340 * s)

            Circle()
                .fill(Color(hex: "#C0C0C0"))
                .frame(width: 16 * s, height: 16 * s)
                .offset(x: 209 * s, y: -426 * s)

            // Bottom glow / feet
            HStack(spacing: 600 * s) {
                ForEach(0..<2) { _ in
                    RoundedRectangle(cornerRadius: 8 * s)
                        .fill(Color(hex: "#3D1F0A"))
                        .frame(width: 60 * s, height: 24 * s)
                }
            }
            .offset(y: 345 * s)
        }
        .frame(width: size, height: size)
    }
}


#Preview("Icon 512") {
    AppIconView(size: 512)
        .ignoresSafeArea()
}
