import SwiftUI

/// Source of truth for the app icon: a mint vintage portable radio.
/// Rendered to `AppIcon-1024.png` via Tools/render_icon.swift.
struct AppIconView: View {
    var size: CGFloat = 1024

    private var s: CGFloat { size / 1024 }
    private var c: CGFloat { size / 2 }   // center

    // Palette
    private let bgTop = Color(hex: "#FFFFFF")
    private let bgBottom = Color(hex: "#D7F1EA")
    private let bodyTop = Color(hex: "#C2EEE5")
    private let bodyBottom = Color(hex: "#8AD4C6")
    private let grille = Color(hex: "#1E5149")
    private let dialCream = Color(hex: "#F8F0DC")
    private let dialCreamEdge = Color(hex: "#E6D7B2")
    private let needle = Color(hex: "#FF6B35")

    private var chrome: LinearGradient {
        LinearGradient(colors: [Color(hex: "#FAFAFA"), Color(hex: "#C9CDCE"), Color(hex: "#8E9698")],
                       startPoint: .top, endPoint: .bottom)
    }

    private var mintHandle: LinearGradient {
        LinearGradient(colors: [Color(hex: "#A9DFD4"), Color(hex: "#79C7B8")],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack {
            background
            ZStack {
                antenna
                handle
                radioBody
                speakerGrille
                tuningDial
                sideKnobs
            }
            // Fill more of the tile so the radio doesn't look small inside the icon.
            .scaleEffect(1.14)
            .offset(y: 6 * s)
        }
        .frame(width: size, height: size)
        .clipped()
    }

    // MARK: - Background

    private var background: some View {
        Rectangle()
            .fill(LinearGradient(colors: [bgTop, bgBottom],
                                 startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Antenna (chrome, behind the body, upper-right)

    private var antenna: some View {
        ZStack {
            Capsule()
                .fill(chrome)
                .frame(width: 12 * s, height: 360 * s)
                .rotationEffect(.degrees(28))
                .offset(x: 235 * s, y: -315 * s)
            Circle()
                .fill(chrome)
                .frame(width: 26 * s, height: 26 * s)
                .offset(x: 320 * s, y: -445 * s)
        }
    }

    // MARK: - Carry handle (chrome arc over the top)

    private var handle: some View {
        ZStack {
            // chrome mounting posts at the body shoulders
            Circle().fill(chrome).frame(width: 42 * s, height: 42 * s)
                .offset(x: -300 * s, y: -248 * s)
            Circle().fill(chrome).frame(width: 42 * s, height: 42 * s)
                .offset(x: 300 * s, y: -248 * s)
            HandleArc()
                .stroke(mintHandle, style: StrokeStyle(lineWidth: 38 * s, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
                .shadow(color: Color(hex: "#2E6B63").opacity(0.18), radius: 6 * s, y: 3 * s)
        }
    }

    // MARK: - Body

    private var radioBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 130 * s, style: .continuous)
                .fill(LinearGradient(colors: [bodyTop, bodyBottom],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 884 * s, height: 624 * s)
                .shadow(color: Color(hex: "#2E6B63").opacity(0.30), radius: 34 * s, y: 18 * s)

            // soft top sheen
            RoundedRectangle(cornerRadius: 130 * s, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.clear],
                                     startPoint: .top, endPoint: .center))
                .frame(width: 884 * s, height: 624 * s)
                .blendMode(.softLight)

            RoundedRectangle(cornerRadius: 130 * s, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 3 * s)
                .frame(width: 884 * s, height: 624 * s)
        }
        .offset(y: 40 * s)
    }

    // MARK: - Speaker grille (left, horizontal slots)

    private var speakerGrille: some View {
        VStack(alignment: .leading, spacing: 30 * s) {
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(grille)
                    .frame(width: (300 - CGFloat(abs(i - 2)) * 22) * s, height: 22 * s)
            }
        }
        .frame(width: 300 * s, alignment: .leading)
        .offset(x: -228 * s, y: 60 * s)
    }

    // MARK: - Tuning dial (right)

    private var tuningDial: some View {
        ZStack {
            // chrome bezel
            Circle().fill(chrome)
                .frame(width: 408 * s, height: 408 * s)
                .shadow(color: .black.opacity(0.25), radius: 12 * s, y: 6 * s)
            Circle().stroke(Color.white.opacity(0.6), lineWidth: 4 * s)
                .frame(width: 408 * s, height: 408 * s)

            // cream face
            Circle()
                .fill(RadialGradient(colors: [dialCream, dialCreamEdge],
                                     center: .center, startRadius: 0, endRadius: 180 * s))
                .frame(width: 348 * s, height: 348 * s)

            // frequency ticks around the upper arc
            ForEach(0..<24, id: \.self) { i in
                let isMajor = i % 4 == 0
                Rectangle()
                    .fill(Color(hex: "#3A2E1A").opacity(isMajor ? 0.85 : 0.5))
                    .frame(width: (isMajor ? 4 : 2.5) * s, height: (isMajor ? 22 : 13) * s)
                    .offset(y: -150 * s)
                    .rotationEffect(.degrees(-120 + Double(i) * (240.0 / 23.0)))
            }

            // central chrome knob
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#F2F4F4"), Color(hex: "#9AA2A4"), Color(hex: "#6E7678")],
                                     center: UnitPoint(x: 0.38, y: 0.34), startRadius: 0, endRadius: 90 * s))
                .frame(width: 150 * s, height: 150 * s)
                .shadow(color: .black.opacity(0.35), radius: 8 * s, y: 4 * s)
            Circle().stroke(Color.white.opacity(0.5), lineWidth: 3 * s)
                .frame(width: 150 * s, height: 150 * s)
            Circle().fill(Color(hex: "#2A2E2F"))
                .frame(width: 26 * s, height: 26 * s)

            // orange tuning needle
            Capsule()
                .fill(needle)
                .frame(width: 6 * s, height: 158 * s)
                .offset(y: -82 * s)
                .rotationEffect(.degrees(22))
        }
        .offset(x: 188 * s, y: 56 * s)
    }

    // MARK: - Side knobs (chrome, peeking at body edges)

    private var sideKnobs: some View {
        ZStack {
            Capsule().fill(chrome)
                .frame(width: 54 * s, height: 92 * s)
                .offset(x: -454 * s, y: 36 * s)
            Capsule().fill(chrome)
                .frame(width: 54 * s, height: 92 * s)
                .offset(x: 454 * s, y: 36 * s)
        }
    }
}

/// The squared chrome carry handle that arcs over the radio body.
private struct HandleArc: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 1024
        let cX = rect.midX
        let halfW = 300 * s
        let baseY = rect.midY - 250 * s
        let topY = baseY - 215 * s
        let r = 70 * s
        var p = Path()
        p.move(to: CGPoint(x: cX - halfW, y: baseY))
        p.addLine(to: CGPoint(x: cX - halfW, y: topY + r))
        p.addQuadCurve(to: CGPoint(x: cX - halfW + r, y: topY),
                       control: CGPoint(x: cX - halfW, y: topY))
        p.addLine(to: CGPoint(x: cX + halfW - r, y: topY))
        p.addQuadCurve(to: CGPoint(x: cX + halfW, y: topY + r),
                       control: CGPoint(x: cX + halfW, y: topY))
        p.addLine(to: CGPoint(x: cX + halfW, y: baseY))
        return p
    }
}

#Preview("Icon 512") {
    AppIconView(size: 512)
        .ignoresSafeArea()
}
