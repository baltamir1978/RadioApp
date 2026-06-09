import SwiftUI
import AppKit

// Standalone renderer for the app icon. Compiled together with
// ../RadioApp/AppIconView.swift to export the 1024 PNG.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//   xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macos14.0 \
//     RadioApp/AppIconView.swift Tools/render_icon_main.swift -o /tmp/rendericon
//   /tmp/rendericon RadioApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

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

@main
enum IconRenderer {
    static func main() {
        MainActor.assumeIsolated {
            let outPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
            let renderer = ImageRenderer(content: AppIconView(size: 1024).ignoresSafeArea())
            renderer.scale = 1.0
            guard let cg = renderer.cgImage else { fatalError("render failed") }

            // Flatten onto opaque white — App Store icons must have no alpha channel.
            let w = cg.width, h = cg.height
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let opaque = ctx.makeImage() else { fatalError("flatten failed") }

            let rep = NSBitmapImageRep(cgImage: opaque)
            guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
            try! data.write(to: URL(fileURLWithPath: outPath))
            print("wrote \(outPath) (\(w)x\(h))")
        }
    }
}
