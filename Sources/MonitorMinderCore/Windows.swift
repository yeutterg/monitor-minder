import AppKit
import ApplicationServices

/// A saved window: which app it belongs to, how to recognise it, and where it sits relative to
/// the top-left corner of its display (so it lands right even if the display moved).
public struct WindowState: Codable, Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var title: String
    /// Front-to-back position among the app's windows when saved; the fallback for matching.
    public var index: Int
    public var display: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(bundleID: String, appName: String, title: String, index: Int, display: String,
                x: Double, y: Double, width: Double, height: Double) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.index = index
        self.display = display
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Pairs saved windows with open ones: identical titles first, then the rest in saved order.
    /// Returns (saved index, open index) pairs.
    public static func match(saved: [WindowState], openTitles: [String]) -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        var freeOpen = Set(openTitles.indices)
        var unmatched: [Int] = []
        for (i, s) in saved.enumerated() {
            if !s.title.isEmpty, let j = openTitles.indices.first(where: { freeOpen.contains($0) && openTitles[$0] == s.title }) {
                pairs.append((i, j))
                freeOpen.remove(j)
            } else {
                unmatched.append(i)
            }
        }
        let rest = freeOpen.sorted()
        for (i, j) in zip(unmatched.sorted { saved[$0].index < saved[$1].index }, rest) { pairs.append((i, j)) }
        return pairs
    }
}

/// Window capture and placement through the Accessibility API. Only standard, visible windows on
/// the current Space are seen; full-screen and minimized windows are left alone.
@MainActor
public enum Windows {
    public static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that points to Privacy & Security › Accessibility.
    public static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    public static func capture(on displays: [DisplayState]) -> [WindowState] {
        guard trusted else { return [] }
        var result: [WindowState] = []
        for app in regularApps() {
            guard let bundleID = app.bundleIdentifier else { continue }
            for (i, w) in windows(of: app.processIdentifier).enumerated() {
                guard let d = display(containing: w.frame, in: displays) else { continue }
                result.append(WindowState(
                    bundleID: bundleID, appName: app.localizedName ?? bundleID, title: w.title, index: i,
                    display: d.key, x: w.frame.minX - Double(d.x), y: w.frame.minY - Double(d.y),
                    width: w.frame.width, height: w.frame.height))
            }
        }
        return result
    }

    /// Moves open windows back to their saved places. Returns how many moved.
    @discardableResult
    public static func restore(_ saved: [WindowState], on displays: [DisplayState]) -> Int {
        guard trusted else { return 0 }
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let wanted = Dictionary(grouping: saved, by: \.bundleID)
        var moved = 0
        for app in regularApps() {
            guard let bundleID = app.bundleIdentifier, let appSaved = wanted[bundleID] else { continue }
            let open = windows(of: app.processIdentifier)
            for (i, j) in WindowState.match(saved: appSaved, openTitles: open.map(\.title)) {
                let s = appSaved[i]
                guard let d = byKey[s.display] else { continue }
                let target = CGRect(x: Double(d.x) + s.x, y: Double(d.y) + s.y,
                                    width: min(s.width, Double(d.width)), height: min(s.height, Double(d.height)))
                if target.integral != open[j].frame.integral {
                    setFrame(open[j].element, target)
                    moved += 1
                }
            }
        }
        return moved
    }

    // MARK: Accessibility plumbing

    private struct OpenWindow {
        let element: AXUIElement
        let title: String
        let frame: CGRect
    }

    private static func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
    }

    private static func windows(of pid: pid_t) -> [OpenWindow] {
        let app = AXUIElementCreateApplication(pid)
        // A hung app shouldn't stall the menu.
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let list = value(app, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return list.compactMap { w in
            guard value(w, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                  value(w, kAXMinimizedAttribute) as? Bool != true,
                  value(w, "AXFullScreen") as? Bool != true,
                  let origin = point(w, kAXPositionAttribute), let size = size(w, kAXSizeAttribute)
            else { return nil }
            return OpenWindow(element: w, title: value(w, kAXTitleAttribute) as? String ?? "",
                              frame: CGRect(origin: origin, size: size))
        }
    }

    /// The display showing most of a window. Window and display frames share the same global,
    /// top-left-origin coordinate space.
    private static func display(containing frame: CGRect, in displays: [DisplayState]) -> DisplayState? {
        let area: (DisplayState) -> CGFloat = { d in
            let r = d.frame.intersection(frame)
            return r.isNull ? 0 : r.width * r.height
        }
        return displays.filter { $0.mirrorOf == nil && area($0) > 0 }.max { area($0) < area($1) }
    }

    private static func setFrame(_ w: AXUIElement, _ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        // Position, size, then position again: moving to a smaller display can clamp the size,
        // and resizing near an edge can nudge the position.
        if let p = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s) }
        if let p = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p) }
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &v) == .success ? v : nil
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        return (v as! AXValue)
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var p = CGPoint.zero
        guard let v = axValue(element, attribute), AXValueGetValue(v, .cgPoint, &p) else { return nil }
        return p
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var s = CGSize.zero
        guard let v = axValue(element, attribute), AXValueGetValue(v, .cgSize, &s) else { return nil }
        return s
    }
}
