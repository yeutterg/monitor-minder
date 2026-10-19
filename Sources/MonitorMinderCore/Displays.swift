import AppKit
import CoreGraphics

/// Reads and applies display arrangements with the public Quartz Display Services API.
@MainActor
public enum Displays {
    public struct Live {
        public let id: CGDirectDisplayID
        public let state: DisplayState
    }

    /// Every online display, including mirrored ones.
    public static func live() -> [Live] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        ids = Array(ids.prefix(Int(count)))

        // Identical monitors without serial numbers report the same vendor/model/serial. Tell
        // them apart by unit number, which follows the port they're connected to.
        var keys: [CGDirectDisplayID: String] = [:]
        for (base, twins) in Dictionary(grouping: ids, by: baseKey) {
            let ordered = twins.sorted { CGDisplayUnitNumber($0) < CGDisplayUnitNumber($1) }
            for (i, id) in ordered.enumerated() { keys[id] = ordered.count > 1 ? "\(base)#\(i + 1)" : base }
        }

        return ids.compactMap { id in
            guard let mode = CGDisplayCopyDisplayMode(id), let key = keys[id] else { return nil }
            let bounds = CGDisplayBounds(id)
            let master = CGDisplayMirrorsDisplay(id)
            let state = DisplayState(
                key: key,
                systemName: name(of: id),
                x: Int(bounds.minX), y: Int(bounds.minY),
                width: Int(bounds.width), height: Int(bounds.height),
                pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate,
                isMain: CGDisplayIsMain(id) != 0,
                mirrorOf: master == kCGNullDirectDisplay ? nil : keys[master])
            return Live(id: id, state: state)
        }
    }

    public static func current() -> [DisplayState] { live().map(\.state) }

    private static func baseKey(_ id: CGDirectDisplayID) -> String {
        if CGDisplayIsBuiltin(id) != 0 { return "builtin" }
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    private static func name(of id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? (CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display")
    }

    /// Applies a saved arrangement: modes and mirroring first, then positions, each committed
    /// permanently so macOS also remembers it. Returns notes about anything it couldn't do.
    @discardableResult
    public static func apply(_ target: [DisplayState]) -> [String] {
        var notes: [String] = []
        let live = Dictionary(live().map { ($0.state.key, $0) }, uniquingKeysWith: { a, _ in a })

        // Modes and mirroring change display sizes, so they go in before positions.
        var changes = false
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return ["Couldn't start a display change"] }
        for t in target {
            guard let l = live[t.key] else { notes.append("\(t.systemName) isn't connected"); continue }
            let master = t.mirrorOf.flatMap { live[$0]?.id } ?? kCGNullDirectDisplay
            if CGDisplayMirrorsDisplay(l.id) != master {
                CGConfigureDisplayMirrorOfDisplay(config, l.id, master)
                changes = true
            }
            if t.mirrorOf == nil, needsModeChange(l.state, t) {
                if let mode = mode(for: t, on: l.id) {
                    CGConfigureDisplayWithDisplayMode(config, l.id, mode, nil)
                    changes = true
                } else {
                    notes.append("\(t.systemName) doesn't offer \(t.sizeText) right now")
                }
            }
        }
        if changes {
            let err = CGCompleteDisplayConfiguration(config, .permanently)
            if err != .success { notes.append("macOS rejected the resolution change (\(err.rawValue))") }
        } else {
            CGCancelDisplayConfiguration(config)
        }

        // Positions. The saved main display is at (0, 0), which also makes it main again.
        let after = Dictionary(self.live().map { ($0.state.key, $0) }, uniquingKeysWith: { a, _ in a })
        let moves = target.filter { t in
            guard t.mirrorOf == nil, let l = after[t.key] else { return false }
            return l.state.x != t.x || l.state.y != t.y
        }
        guard !moves.isEmpty else { return notes }
        guard CGBeginDisplayConfiguration(&config) == .success else { return notes + ["Couldn't start a display change"] }
        for t in target where t.mirrorOf == nil {
            guard let l = after[t.key] else { continue }
            CGConfigureDisplayOrigin(config, l.id, Int32(t.x), Int32(t.y))
        }
        let err = CGCompleteDisplayConfiguration(config, .permanently)
        if err != .success { notes.append("macOS rejected the arrangement (\(err.rawValue))") }
        return notes
    }

    private static func needsModeChange(_ current: DisplayState, _ target: DisplayState) -> Bool {
        current.width != target.width || current.height != target.height
            || current.pixelWidth != target.pixelWidth || current.pixelHeight != target.pixelHeight
            || (target.refreshRate > 0 && current.refreshHz != target.refreshHz)
    }

    /// The display mode matching a saved state: same size and pixel density, the saved refresh
    /// rate when available, otherwise the highest one at that size.
    private static func mode(for target: DisplayState, on id: CGDirectDisplayID) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        let sized = modes.filter {
            $0.width == target.width && $0.height == target.height
                && $0.pixelWidth == target.pixelWidth && $0.pixelHeight == target.pixelHeight
        }
        if target.refreshRate > 0, let exact = sized.first(where: { Int($0.refreshRate.rounded()) == target.refreshHz }) {
            return exact
        }
        return sized.max { $0.refreshRate < $1.refreshRate }
    }
}
