// Renders the DMG window background, packaging/dmg/background.tiff (1x + 2x, LZW).
// Layout (points, origin top-left) must match packaging/dmg/settings.py: window 600×360, icon size 112,
// Swoop.app at (160, 200), Applications at (440, 200).
//
// Finder doesn't always honor the window size a DMG asks for (some Macs open it larger), and it draws the
// picture at its own size from the top-left, white beyond it. So the canvas is much larger than the window:
// the design sits in the top-left 600×360 and fades into a flat color that fills the rest (flat areas also
// keep the LZW-compressed file small).
//
//   swiftc -O packaging/dmg/background.swift -o build/dmg-background && build/dmg-background packaging/dmg
import AppKit
import SwiftUI

let window = CGSize(width: 600, height: 360)
let canvas = CGSize(width: 1400, height: 900)
let appCenter = CGPoint(x: 160, y: 200)
let applicationsCenter = CGPoint(x: 440, y: 200)

let orange = Color(red: 0.95, green: 0.42, blue: 0.16)
let orangeLight = Color(red: 1.00, green: 0.58, blue: 0.24)
let violet = Color(red: 0.45, green: 0.36, blue: 0.95)
/// The flat color everything fades into (the Swoop theme's light surface).
let base = Color(red: 0.985, green: 0.965, blue: 0.960)

/// A gentle arc from the app to Applications, with an arrowhead: the "swoop".
struct SwoopArrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let start = CGPoint(x: r.minX, y: r.maxY - 6), tip = CGPoint(x: r.maxX, y: r.maxY - 6)
        p.move(to: start)
        p.addQuadCurve(to: tip, control: CGPoint(x: r.midX, y: r.minY - 14))
        // Arrowhead, roughly along the curve's end tangent (pointing down-right).
        p.move(to: CGPoint(x: tip.x - 15, y: tip.y - 3))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x - 3, y: tip.y - 15))
        return p
    }
}

struct Background: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            base
            // Brand glows over the window area; they fade out into `base` well inside the canvas.
            RadialGradient(colors: [orange.opacity(0.20), .clear], center: .center, startRadius: 0, endRadius: 260)
                .frame(width: 600, height: 600).position(x: 130, y: 120)
            RadialGradient(colors: [violet.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: 300)
                .frame(width: 700, height: 700).position(x: 520, y: 330)

            VStack(spacing: 6) {
                Text("Install Swoop")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.12))
                Text("Drag Swoop to your Applications folder")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .frame(width: window.width)
            .position(x: window.width / 2, y: 68)

            SwoopArrow()
                .stroke(LinearGradient(colors: [orangeLight.opacity(0.55), orange], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 110, height: 34)
                .position(x: (appCenter.x + applicationsCenter.x) / 2, y: appCenter.y - 8)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }
}

guard CommandLine.arguments.count == 2 else { fatalError("usage: dmg-background <out dir>") }
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

MainActor.assumeIsolated {
    let image = NSImage(size: canvas)
    for scale in [1, 2] {
        let renderer = ImageRenderer(content: Background())
        renderer.scale = CGFloat(scale)
        renderer.isOpaque = true
        renderer.colorMode = .nonLinear
        guard let cg = renderer.cgImage else { fatalError("render failed") }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = canvas // 72 dpi at 1x, 144 dpi at 2x: Finder picks the right one
        image.addRepresentation(rep)
    }
    let tiff = image.tiffRepresentation(using: .lzw, factor: 0)!
    try! tiff.write(to: outDir.appendingPathComponent("background.tiff"))
    print("wrote background.tiff (\(tiff.count / 1024) KB)")
}
