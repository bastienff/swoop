// Generates Swoop's app icon set. Usage: swift Tools/make_icon.swift <appiconset dir> [master.png]
// The optional second path also writes the 1024 px master (docs/design/brand/icon/swoop-icon-1024.png).
// Arrow geometry is shared with `MenuBarController.statusImage` and the docs SVG: keep them in sync
// (docs/design/brand/README.md).
import AppKit

let dir = CommandLine.arguments[1]
let masterPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

/// One swap arrow pointing right, in unit icon space: a round tail tapering up into a swept head.
/// Two subpaths with the same winding (shaft, head), so a nonzero fill is their union.
func arrowPath() -> CGPath {
    let y: CGFloat = 0.616, x0: CGFloat = 0.27, xe: CGFloat = 0.60
    let w0: CGFloat = 0.05, w1: CGFloat = 0.09, head: CGFloat = 0.14, headW: CGFloat = 0.215, sweep: CGFloat = 0.05
    let p = CGMutablePath()
    // Shaft (counterclockwise): bottom edge, front, top edge, round tail.
    p.move(to: CGPoint(x: x0, y: y - w0 / 2))
    p.addLine(to: CGPoint(x: xe, y: y - w1 / 2))
    p.addLine(to: CGPoint(x: xe, y: y + w1 / 2))
    p.addLine(to: CGPoint(x: x0, y: y + w0 / 2))
    p.addArc(center: CGPoint(x: x0, y: y), radius: w0 / 2, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
    p.closeSubpath()
    // Head (counterclockwise): convex outer edges, concave back edges, barbs swept back by `sweep`.
    let tip = CGPoint(x: xe + head, y: y), notch = CGPoint(x: xe - sweep * 0.2, y: y)
    let top = CGPoint(x: xe - sweep, y: y + headW / 2), bottom = CGPoint(x: xe - sweep, y: y - headW / 2)
    let cx = (2 * top.x + tip.x) / 3
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    func outward(_ a: CGPoint, _ b: CGPoint) -> CGPoint { let m = mid(a, b); return CGPoint(x: m.x + (m.x - cx) * 0.1, y: m.y + (m.y - y) * 0.1) }
    func inward(_ a: CGPoint, _ b: CGPoint) -> CGPoint { let m = mid(a, b); return CGPoint(x: m.x + sweep * 0.7, y: m.y) }
    p.move(to: notch)
    p.addQuadCurve(to: bottom, control: inward(notch, bottom))
    p.addQuadCurve(to: tip, control: outward(bottom, tip))
    p.addQuadCurve(to: top, control: outward(tip, top))
    p.addQuadCurve(to: notch, control: inward(top, notch))
    p.closeSubpath()
    return p
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s) // unit space; shadow metrics are in pixels
    let body = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    let shape = CGPath(roundedRect: body, cornerWidth: 0.18, cornerHeight: 0.18, transform: nil)
    // Soft drop shadow under the squircle.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    // Warm orange gradient.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        CGColor(srgbRed: 1.0, green: 0.66, blue: 0.22, alpha: 1), CGColor(srgbRed: 0.94, green: 0.32, blue: 0.16, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0.9), end: CGPoint(x: 0, y: 0.1), options: [])
    // Swap arrows: → on top, ← below (the same arrow turned 180°), both white, with a warm lift shadow.
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.016,
                  color: CGColor(srgbRed: 0.5, green: 0.1, blue: 0, alpha: 0.32))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    var turn = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1, ty: 1)
    for path in [arrowPath(), arrowPath().copy(using: &turn)!] {
        ctx.setFillColor(.white); ctx.setStrokeColor(.white)
        ctx.addPath(path); ctx.fillPath()
        ctx.addPath(path); ctx.setLineWidth(0.014); ctx.setLineJoin(.round); ctx.strokePath() // rounds every corner
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    // Hairline rim.
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 0.002, dy: 0.002), cornerWidth: 0.178, cornerHeight: 0.178, transform: nil))
    ctx.setLineWidth(0.004); ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22)); ctx.strokePath()
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
if let masterPath { try! render(1024).write(to: URL(fileURLWithPath: masterPath)) }
