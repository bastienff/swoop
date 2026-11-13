// Composites README images from transparent panel captures (DEBUG `swctl demo` + `swctl snapshot <png> clear`).
// Usage: swiftc -O Tools/make_readme_assets.swift -o build/make_readme_assets
//        build/make_readme_assets <grid.png> <search.png> <icon.png> <out dir> [App Name] [tagline]
// Produces: swoop-grid.png, swoop-search.png, social-preview.png (1280×640, GitHub social card).
// The wallpaper is generated (no third-party artwork); panel styling mirrors the app's HUD material.
import AppKit
import CoreImage

let args = CommandLine.arguments
guard args.count >= 5 else {
    print("usage: make_readme_assets <grid.png> <search.png> <icon.png> <outdir> [name] [tagline]"); exit(1)
}
let outDir = URL(fileURLWithPath: args[4])
let appName = args.count > 5 ? args[5] : "Swoop"
let tagline = args.count > 6 ? args[6] : "Just a window switcher for macOS."
let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("cannot read \(path)"); exit(1) }
    return img
}

func context(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    return c
}

func save(_ img: CGImage, _ name: String, maxWidth: Int? = nil) {
    var img = img
    if let maxWidth, img.width > maxWidth {
        let h = Int(Double(img.height) * Double(maxWidth) / Double(img.width))
        let c = context(maxWidth, h)
        c.draw(img, in: CGRect(x: 0, y: 0, width: maxWidth, height: h))
        img = c.makeImage()!
    }
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path) \(img.width)×\(img.height)")
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

/// Deep indigo wallpaper with soft diagonal light bands (in the spirit of the reference captures).
func wallpaper(_ w: Int, _ h: Int) -> CGImage {
    let c = context(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    let base = CGGradient(colorsSpace: sRGB, colors: [rgb(0.20, 0.19, 0.40), rgb(0.10, 0.10, 0.22), rgb(0.06, 0.06, 0.13)] as CFArray,
                          locations: [0, 0.55, 1])!
    c.drawLinearGradient(base, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Large soft glow, upper left.
    let glow = CGGradient(colorsSpace: sRGB, colors: [rgb(0.42, 0.40, 0.78, 0.45), rgb(0.42, 0.40, 0.78, 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(glow, startCenter: CGPoint(x: W * 0.18, y: H * 0.95), startRadius: 0,
                         endCenter: CGPoint(x: W * 0.18, y: H * 0.95), endRadius: max(W, H) * 0.6, options: [])
    // Curved light bands: wide soft stroke + thin bright edge.
    let s = max(W, H)
    func band(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, width: CGFloat, alpha: Double) {
        let path = CGMutablePath()
        path.move(to: p0); path.addCurve(to: p1, control1: c1, control2: c2)
        c.saveGState()
        c.setLineCap(.round)
        c.addPath(path); c.setLineWidth(width * 6); c.setStrokeColor(rgb(0.45, 0.42, 0.85, alpha * 0.18)); c.strokePath()
        c.addPath(path); c.setLineWidth(width * 2); c.setStrokeColor(rgb(0.60, 0.57, 0.95, alpha * 0.30)); c.strokePath()
        c.addPath(path); c.setLineWidth(width * 0.5); c.setStrokeColor(rgb(0.86, 0.85, 1.0, alpha)); c.strokePath()
        c.restoreGState()
    }
    band(CGPoint(x: -0.05 * W, y: 0.30 * H), CGPoint(x: 0.30 * W, y: 0.45 * H), CGPoint(x: 0.60 * W, y: 0.70 * H), CGPoint(x: 1.05 * W, y: 1.10 * H), width: s * 0.004, alpha: 0.85)
    band(CGPoint(x: 0.35 * W, y: -0.05 * H), CGPoint(x: 0.55 * W, y: 0.20 * H), CGPoint(x: 0.85 * W, y: 0.35 * H), CGPoint(x: 1.05 * W, y: 0.45 * H), width: s * 0.003, alpha: 0.6)
    band(CGPoint(x: 0.70 * W, y: 1.05 * H), CGPoint(x: 0.78 * W, y: 0.90 * H), CGPoint(x: 0.88 * W, y: 0.80 * H), CGPoint(x: 1.05 * W, y: 0.72 * H), width: s * 0.0025, alpha: 0.5)
    // Gentle blur so bands read as light, not lines.
    let img = CIImage(cgImage: c.makeImage()!)
    let blurred = img.clampedToExtent().applyingGaussianBlur(sigma: Double(s) * 0.0015).cropped(to: img.extent)
    return ci.createCGImage(blurred, from: img.extent)!
}

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Background + frosted HUD panel + captured content, centered with `margin` around the panel.
func composite(content: CGImage, marginX: Int, marginY: Int, radius: CGFloat) -> CGImage {
    let w = content.width + 2 * marginX, h = content.height + 2 * marginY
    let bg = wallpaper(w, h)
    let panel = CGRect(x: marginX, y: marginY, width: content.width, height: content.height)
    let c = context(w, h)
    c.draw(bg, in: CGRect(x: 0, y: 0, width: w, height: h))
    // Drop shadow.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -radius * 0.5), blur: radius * 1.6, color: rgb(0, 0, 0, 0.55))
    c.addPath(roundedPath(panel, radius)); c.setFillColor(rgb(0.08, 0.08, 0.12, 1)); c.fillPath()
    c.restoreGState()
    // Frosted glass: blurred wallpaper under the panel, darkened like the HUD material.
    let bgCI = CIImage(cgImage: bg)
    let frost = ci.createCGImage(bgCI.clampedToExtent().applyingGaussianBlur(sigma: radius * 1.2).cropped(to: bgCI.extent), from: bgCI.extent)!
    c.saveGState()
    c.addPath(roundedPath(panel, radius)); c.clip()
    c.draw(frost, in: CGRect(x: 0, y: 0, width: w, height: h))
    c.setFillColor(rgb(0.10, 0.10, 0.14, 0.62)); c.fill(panel)
    let sheen = CGGradient(colorsSpace: sRGB, colors: [rgb(1, 1, 1, 0.06), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(sheen, start: CGPoint(x: panel.minX, y: panel.maxY), end: CGPoint(x: panel.midX, y: panel.minY), options: [])
    c.draw(content, in: panel)
    c.restoreGState()
    // Hairline border.
    c.addPath(roundedPath(panel.insetBy(dx: 0.5, dy: 0.5), radius)); c.setLineWidth(1.5)
    c.setStrokeColor(rgb(1, 1, 1, 0.16)); c.strokePath()
    return c.makeImage()!
}

let scale: CGFloat = 2 // captures are @2x
let radius = 36 * scale

let grid = load(args[1]), search = load(args[2]), icon = load(args[3])
save(composite(content: grid, marginX: 110, marginY: 110, radius: radius), "swoop-grid.png", maxWidth: 2000)
save(composite(content: search, marginX: 170, marginY: 130, radius: radius), "swoop-search.png", maxWidth: 1200)

// Social preview (GitHub recommends 1280×640): wallpaper, icon, name, tagline, a slice of the search panel.
do {
    let W = 1280, H = 640
    let c = context(W, H)
    c.draw(wallpaper(W, H), in: CGRect(x: 0, y: 0, width: W, height: H))
    let iconSize: CGFloat = 220
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0, 0, 0, 0.5))
    c.draw(icon, in: CGRect(x: 110, y: (CGFloat(H) - iconSize) / 2 + 10, width: iconSize, height: iconSize))
    c.restoreGState()
    let ns = NSGraphicsContext(cgContext: c, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    let title = NSAttributedString(string: appName, attributes: [
        .font: NSFont.systemFont(ofSize: 104, weight: .bold), .foregroundColor: NSColor.white])
    title.draw(at: CGPoint(x: 380, y: 300))
    let sub = NSAttributedString(string: tagline, attributes: [
        .font: NSFont.systemFont(ofSize: 38, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.72)])
    sub.draw(at: CGPoint(x: 384, y: 236))
    let keys = NSAttributedString(string: "⌥ Tab  ·  type  ·  ↩", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 28, weight: .semibold), .foregroundColor: NSColor(calibratedRed: 0.78, green: 0.76, blue: 1, alpha: 0.9)])
    keys.draw(at: CGPoint(x: 386, y: 170))
    NSGraphicsContext.restoreGraphicsState()
    save(c.makeImage()!, "social-preview.png")
}
