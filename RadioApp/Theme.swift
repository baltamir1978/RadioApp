import SwiftUI

/// Central color tokens for the app, derived from the mint vintage-radio icon.
/// Each token resolves to a light value in light mode and a dark teal value in
/// dark mode, so text using `.primary`/`.secondary` stays legible in both.
extension Color {
    /// Primary brand accent — deep teal (the icon's grille/dial green); brightened in dark mode.
    static let brand = Color(light: "#2E9E8F", dark: "#5FD3C2")
    /// Soft mint screen background.
    static let appBackground = Color(light: "#EAF7F3", dark: "#0E1B19")
    /// Slightly stronger mint for nav bars and raised surfaces.
    static let mintSurface = Color(light: "#D6EFE8", dark: "#16302C")
}
