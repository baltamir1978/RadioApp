import SwiftUI

/// Central color tokens for the app, derived from the mint vintage-radio icon.
/// Each token resolves to a light value in light mode and a dark teal value in
/// dark mode, so text using `.primary`/`.secondary` stays legible in both.
extension Color {
    /// Primary brand accent — deep teal (the icon's grille/dial green); brightened in dark mode.
    ///
    /// The light value is deliberately darker than the icon's mint: the accent carries small
    /// text ("EN DIRECTO", toolbar glyphs) on the mint surfaces, and the original #2E9E8F only
    /// reached 2.7:1 against them — short of the 4.5:1 WCAG AA asks for. #1F6F64 reaches 4.9:1
    /// on the nav bar and 5.4:1 on the screen background while keeping the same hue.
    static let brand = Color(light: "#1F6F64", dark: "#5FD3C2")
    /// Soft mint screen background.
    static let appBackground = Color(light: "#EAF7F3", dark: "#0E1B19")
    /// Slightly stronger mint for nav bars and raised surfaces.
    static let mintSurface = Color(light: "#D6EFE8", dark: "#16302C")
}
