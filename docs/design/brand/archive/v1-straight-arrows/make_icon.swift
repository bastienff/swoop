// Generates Swoop's app icon set. Usage: swift Tools/make_icon.swift <appiconset dir>
import AppKit
let dir = CommandLine.arguments[1]
/// Horizontal arrow polygon from `p` to the tip `q` (shaft width `w`, head length `h`).
func arrow(from p: CGPoint, to q: CGPoint, width w: CGFloat, head h: CGFloat) -> NSBezierPath {
    let dir: CGFloat = q.x >= p.x ? 1 : -1, bx = q.x - dir * h
    let path = NSBezierPath()
    path.move(to: CGPoint(x: p.x, y: p.y + w / 2))
    path.line(to: CGPoint(x: bx, y: q.y + w / 2))
    path.line(to: CGPoint(x: bx, y: q.y + h * 0.8))
    path.line(to: q)
    path.line(to: CGPoint(x: bx, y: q.y - h * 0.8))
    path.line(to: CGPoint(x: bx, y: q.y - w / 2))
    path.line(to: CGPoint(x: p.x, y: p.y - w / 2))
    path.close()
    return path
}
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1, body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    // Soft drop shadow under the squircle.
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow(); drop.shadowColor = NSColor(white: 0, alpha: 0.3); drop.shadowBlurRadius = s * 0.02
    drop.shadowOffset = NSSize(width: 0, height: -s * 0.008); drop.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    // Warm orange gradient.
    NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.66, blue: 0.22, alpha: 1), NSColor(srgbRed: 0.94, green: 0.32, blue: 0.16, alpha: 1)])!
        .draw(in: shape, angle: -90)
    // Swap arrows: → on top (solid), ← below (slightly translucent).
    let w = body.height * 0.085, h = body.height * 0.16
    let x0 = body.minX + body.width * 0.2, x1 = body.maxX - body.width * 0.2, dy = body.height * 0.13
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow(); glow.shadowColor = NSColor(srgbRed: 0.5, green: 0.1, blue: 0, alpha: 0.3)
    glow.shadowBlurRadius = s * 0.016; glow.shadowOffset = NSSize(width: 0, height: -s * 0.008); glow.set()
    NSColor.white.setFill()
    arrow(from: CGPoint(x: x0, y: body.midY + dy), to: CGPoint(x: x1, y: body.midY + dy), width: w, head: h).fill()
    NSColor.white.withAlphaComponent(0.8).setFill()
    arrow(from: CGPoint(x: x1, y: body.midY - dy), to: CGPoint(x: x0, y: body.midY - dy), width: w, head: h).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
var images: [[String: String]] = []
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for sc in scales {
        let name = "icon_\(pt)x\(pt)\(sc == 2 ? "@2x" : "").png"
        try! render(pt * sc).write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(sc)x", "filename": name])
    }
}
let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(dir)/Contents.json"))
