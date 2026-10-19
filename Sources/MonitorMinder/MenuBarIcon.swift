import AppKit

/// The menu bar glyph: a smaller monitor at the back left, partly hidden by a larger one in front.
/// Drawn once as a template image so it follows the menu bar's appearance.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: true) { _ in
            NSColor.black.setStroke()
            let line: (NSBezierPath) -> Void = { p in
                p.lineWidth = 1.3
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.stroke()
            }
            // Back monitor: only the parts not covered by the front one.
            let back = NSBezierPath()
            back.move(to: NSPoint(x: 5.4, y: 7.6))
            back.line(to: NSPoint(x: 1.6, y: 7.6))
            back.appendArc(withCenter: NSPoint(x: 1.6, y: 6.7), radius: 0.9, startAngle: 90, endAngle: 180)
            back.line(to: NSPoint(x: 0.7, y: 1.6))
            back.appendArc(withCenter: NSPoint(x: 1.6, y: 1.6), radius: 0.9, startAngle: 180, endAngle: 270)
            back.line(to: NSPoint(x: 8.4, y: 0.7))
            back.appendArc(withCenter: NSPoint(x: 8.4, y: 1.6), radius: 0.9, startAngle: 270, endAngle: 360)
            back.line(to: NSPoint(x: 9.3, y: 3.4))
            line(back)
            let backStand = NSBezierPath()
            backStand.move(to: NSPoint(x: 3.6, y: 7.6)); backStand.line(to: NSPoint(x: 3.6, y: 9.2))
            backStand.move(to: NSPoint(x: 2.4, y: 9.6)); backStand.line(to: NSPoint(x: 4.8, y: 9.6))
            line(backStand)
            // Front monitor.
            line(NSBezierPath(roundedRect: NSRect(x: 6.4, y: 3.8, width: 10.9, height: 7), xRadius: 1.1, yRadius: 1.1))
            let stand = NSBezierPath()
            stand.move(to: NSPoint(x: 11.85, y: 10.8)); stand.line(to: NSPoint(x: 11.85, y: 12.7))
            stand.move(to: NSPoint(x: 9.8, y: 13)); stand.line(to: NSPoint(x: 13.9, y: 13))
            line(stand)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Monitor Minder"
        return image
    }()
}
