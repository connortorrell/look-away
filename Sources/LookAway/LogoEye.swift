import AppKit

/// The app icon's eye, glancing aside, as a menu bar template image.
///
/// Drawn from the same geometry as `Resources/Artwork/AppIcon.svg`: an almond
/// from x 18 to 82 with its curves pulled to y 22 and 78, and a pupil of radius
/// 9 at (63, 50), all on a 100-unit square. The stroke is set in points rather
/// than scaled, so it matches the weight of the SF Symbols the other states use.
enum LogoEye {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let scale = rect.width / 64 * 0.95
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: rect.midX + (x - 50) * scale, y: rect.midY + (y - 50) * scale)
            }

            let almond = NSBezierPath()
            almond.move(to: point(18, 50))
            quadCurve(almond, to: point(82, 50), control: point(50, 22))
            quadCurve(almond, to: point(18, 50), control: point(50, 78))
            almond.close()
            almond.lineWidth = 1.5
            almond.lineJoinStyle = .round
            NSColor.black.setStroke()
            almond.stroke()

            let pupil = 9 * scale
            let center = point(63, 50)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - pupil, y: center.y - pupil, width: pupil * 2, height: pupil * 2)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Look Away"
        return image
    }()

    /// The SVG's quadratic curve, as the cubic NSBezierPath draws.
    private static func quadCurve(_ path: NSBezierPath, to end: NSPoint, control: NSPoint) {
        let start = path.currentPoint
        path.curve(
            to: end,
            controlPoint1: NSPoint(x: start.x + (control.x - start.x) * 2 / 3, y: start.y + (control.y - start.y) * 2 / 3),
            controlPoint2: NSPoint(x: end.x + (control.x - end.x) * 2 / 3, y: end.y + (control.y - end.y) * 2 / 3)
        )
    }
}
