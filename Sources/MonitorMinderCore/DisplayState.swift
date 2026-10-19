import CoreGraphics
import Foundation

/// One display as it was (or is) arranged: where it sits in the global desktop, its mode, and
/// whether it mirrors another display. Positions and sizes are in points, the units System
/// Settings shows ("looks like" resolution); the main display sits at (0, 0).
public struct DisplayState: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Stable identity across reconnects: vendor, model and serial number from the display's
    /// EDID, with a `#n` suffix when two connected displays report the same three.
    public var key: String
    /// The name macOS gives the display, used until the user names it.
    public var systemName: String
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// 0 when the display doesn't report one.
    public var refreshRate: Double
    public var isMain: Bool
    /// Key of the display this one mirrors, if any.
    public var mirrorOf: String?

    public var id: String { key }
    public var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public var sizeText: String { "\(width) × \(height)" }
    public var refreshHz: Int { Int(refreshRate.rounded()) }

    public init(key: String, systemName: String, x: Int, y: Int, width: Int, height: Int,
                pixelWidth: Int, pixelHeight: Int, refreshRate: Double, isMain: Bool, mirrorOf: String? = nil) {
        self.key = key
        self.systemName = systemName
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.isMain = isMain
        self.mirrorOf = mirrorOf
    }

    public enum Placement: Equatable, Sendable { case main, mirroring, left, right, above, below }

    /// Where this display sits relative to the main display, for captions like "Left of Studio".
    public func placement(relativeTo main: DisplayState) -> Placement {
        if mirrorOf != nil { return .mirroring }
        if isMain || key == main.key { return .main }
        // Compare offsets in units of the main display's size so wide and tall setups both read right.
        let dx = (frame.midX - main.frame.midX) / max(main.frame.width, 1)
        let dy = (frame.midY - main.frame.midY) / max(main.frame.height, 1)
        if abs(dx) >= abs(dy) { return dx < 0 ? .left : .right }
        return dy < 0 ? .above : .below
    }
}

/// A way the current arrangement differs from a saved one.
public enum Drift: Equatable, Sendable {
    case missing(key: String)
    case moved(key: String, dx: Int, dy: Int)
    case resized(key: String, current: String, saved: String)
    case refresh(key: String, current: Int, saved: Int)
    case mirroring(key: String)

    public var key: String {
        switch self {
        case .missing(let key), .moved(let key, _, _), .resized(let key, _, _),
             .refresh(let key, _, _), .mirroring(let key): key
        }
    }

    /// Differences between a saved arrangement and the current one, in display order.
    public static func between(saved: [DisplayState], current: [DisplayState]) -> [Drift] {
        let live = Dictionary(current.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [Drift] = []
        for s in saved {
            guard let c = live[s.key] else { result.append(.missing(key: s.key)); continue }
            if s.mirrorOf != c.mirrorOf { result.append(.mirroring(key: s.key)); continue }
            if s.width != c.width || s.height != c.height || s.pixelWidth != c.pixelWidth || s.pixelHeight != c.pixelHeight {
                result.append(.resized(key: s.key, current: c.sizeText, saved: s.sizeText))
            } else if s.refreshRate > 0, c.refreshRate > 0, s.refreshHz != c.refreshHz {
                result.append(.refresh(key: s.key, current: c.refreshHz, saved: s.refreshHz))
            }
            // A mirrored display has no position of its own.
            if s.mirrorOf == nil, s.x != c.x || s.y != c.y {
                result.append(.moved(key: s.key, dx: c.x - s.x, dy: c.y - s.y))
            }
        }
        return result
    }
}
