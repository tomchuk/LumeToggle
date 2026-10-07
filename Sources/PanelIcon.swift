import AppKit

/// Custom 18pt template icon: an LED panel (dot grid). Filled + rays when on, slashed when disconnected.
enum PanelIcon {
    enum State { case on, off, disconnected }

    static let on = make(.on)
    static let off = make(.off)
    static let disconnected = make(.disconnected)

    private static func make(_ state: State) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            switch state {
            case .on:
                let body = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 5, width: 15, height: 12),
                                        xRadius: 2.75, yRadius: 2.75)
                dots().forEach { body.appendOval(in: $0) }
                body.windingRule = .evenOdd          // dots become holes
                body.fill()
                stroke([(9, 1, 9, 3.25), (3.25, 1.9, 4.6, 3.6), (14.75, 1.9, 13.4, 3.6)], width: 1.4)
            case .off, .disconnected:
                let body = NSBezierPath(roundedRect: NSRect(x: 2.25, y: 5.75, width: 13.5, height: 10.5),
                                        xRadius: 2, yRadius: 2)
                body.lineWidth = 1.5
                body.stroke()
                dots().forEach { NSBezierPath(ovalIn: $0).fill() }
                if state == .disconnected {
                    NSGraphicsContext.current?.compositingOperation = .clear   // gap around the slash
                    stroke([(2, 1.5, 16.5, 16.5)], width: 3.5)
                    NSGraphicsContext.current?.compositingOperation = .sourceOver
                    stroke([(2, 1.5, 16.5, 16.5)], width: 1.5)
                }
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Lume Cube"
        return img
    }

    private static func dots() -> [NSRect] {
        let r: CGFloat = 0.85
        let xs: [CGFloat] = [5.25, 7.75, 10.25, 12.75]
        let ys: [CGFloat] = [8.25, 11, 13.75]
        return ys.flatMap { y in xs.map { x in NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r) } }
    }

    private static func stroke(_ lines: [(CGFloat, CGFloat, CGFloat, CGFloat)], width: CGFloat) {
        let p = NSBezierPath()
        for (x1, y1, x2, y2) in lines {
            p.move(to: NSPoint(x: x1, y: y1))
            p.line(to: NSPoint(x: x2, y: y2))
        }
        p.lineWidth = width
        p.lineCapStyle = .round
        p.stroke()
    }
}
