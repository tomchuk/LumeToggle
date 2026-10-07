// Renders the app icon into an .iconset: the menu bar's "on" panel glyph, lit, on a
// macOS-style rounded square. Run via `just icon`.
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"

/// Draws on a 1024×1024 canvas, top-left origin, matching PanelIcon's flipped coordinates.
func draw() {
    // Background: Apple's icon grid puts an 824pt rounded square inside the 1024 canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)   // flipped: positive is down visually, so negate
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.22, blue: 0.30, alpha: 1),
                        NSColor(srgbRed: 0.07, green: 0.08, blue: 0.12, alpha: 1)])!
        .draw(in: tilePath, angle: 90)

    // The glyph's 18-unit box, scaled up and centred.
    let s: CGFloat = 32, ox = 512 - 9 * s, oy = 512 - 9 * s
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
    }
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * s, y: oy + y * s) }

    let warm = NSColor(srgbRed: 1.00, green: 0.80, blue: 0.42, alpha: 1)

    // Panel face: warm white gradient, LED dots as holes showing the tile through.
    let face = NSBezierPath(roundedRect: r(1.5, 5, 15, 12), xRadius: 2.75 * s, yRadius: 2.75 * s)
    let rad: CGFloat = 0.85
    for y in [8.25, 11, 13.75] as [CGFloat] {
        for x in [5.25, 7.75, 10.25, 12.75] as [CGFloat] {
            face.appendOval(in: r(x - rad, y - rad, 2 * rad, 2 * rad))
        }
    }
    face.windingRule = .evenOdd
    // Glow, cast by the holed face so the dots stay dark.
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = warm.withAlphaComponent(0.7)
    glow.shadowBlurRadius = 90
    glow.set()
    warm.setFill()
    face.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    face.addClip()
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.97, blue: 0.90, alpha: 1), warm])!
        .draw(in: r(1.5, 5, 15, 12), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Rays.
    let rays = NSBezierPath()
    for (x1, y1, x2, y2) in [(9, 1, 9, 3.25), (3.25, 1.9, 4.6, 3.6), (14.75, 1.9, 13.4, 3.6)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        rays.move(to: p(x1, y1)); rays.line(to: p(x2, y2))
    }
    rays.lineWidth = 1.4 * s
    rays.lineCapStyle = .round
    warm.setStroke()
    rays.stroke()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    // Flip to top-left origin and scale the 1024 canvas down to this size.
    cg.translateBy(x: 0, y: CGFloat(px))
    cg.scaleBy(x: CGFloat(px) / 1024, y: -CGFloat(px) / 1024)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
    }
}
