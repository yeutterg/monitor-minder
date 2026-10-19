import CoreGraphics

/// Geometry for rearranging displays by dragging, as in System Settings: a dropped display snaps
/// flush against a neighbour, never overlaps one, and lines up with nearby edges.
public enum Arrangement {
    /// Where a display dropped at `frame` should land. `others` are the other displays' frames;
    /// `alignWithin` is how close (in points) an edge must be to snap into line with another.
    public static func snap(_ frame: CGRect, to others: [CGRect], alignWithin: CGFloat) -> CGPoint {
        guard !others.isEmpty else { return frame.origin }
        var best: CGPoint?
        var bestDistance = CGFloat.infinity
        for o in others {
            // Keep a real shared edge: at least a tenth of the shorter side, so the pointer can cross.
            let minOverlapY = min(frame.height, o.height) * 0.1
            let minOverlapX = min(frame.width, o.width) * 0.1
            let y = align(clamp(frame.minY, o.minY - frame.height + minOverlapY, o.maxY - minOverlapY),
                          size: frame.height, start: o.minY, end: o.maxY, within: alignWithin)
            let x = align(clamp(frame.minX, o.minX - frame.width + minOverlapX, o.maxX - minOverlapX),
                          size: frame.width, start: o.minX, end: o.maxX, within: alignWithin)
            let candidates = [
                CGPoint(x: o.minX - frame.width, y: y), CGPoint(x: o.maxX, y: y),
                CGPoint(x: x, y: o.minY - frame.height), CGPoint(x: x, y: o.maxY),
            ]
            for c in candidates {
                let placed = CGRect(origin: c, size: frame.size)
                guard !others.contains(where: { overlaps($0, placed) }) else { continue }
                let distance = hypot(c.x - frame.minX, c.y - frame.minY)
                if distance < bestDistance { best = c; bestDistance = distance }
            }
        }
        guard let best else { return frame.origin }
        return CGPoint(x: best.x.rounded(), y: best.y.rounded())
    }

    /// Shifts every display so the one with `main` key sits at (0, 0), which makes it the main
    /// display when applied. Mirrored displays keep their place.
    public static func normalized(_ displays: [DisplayState], main: String) -> [DisplayState] {
        guard let m = displays.first(where: { $0.key == main }) else { return displays }
        let (dx, dy) = (m.x, m.y)
        return displays.map { d in
            var d = d
            if d.mirrorOf == nil { d.x -= dx; d.y -= dy }
            d.isMain = d.key == main
            return d
        }
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let i = a.intersection(b)
        return !i.isNull && i.width > 0.5 && i.height > 0.5
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

    /// Snaps a span's start, end or centre into line with another span when it's close.
    private static func align(_ v: CGFloat, size: CGFloat, start: CGFloat, end: CGFloat, within: CGFloat) -> CGFloat {
        let options = [start, end - size, (start + end - size) / 2]
        guard let nearest = options.min(by: { abs($0 - v) < abs($1 - v) }), abs(nearest - v) <= within else { return v }
        return nearest
    }
}
