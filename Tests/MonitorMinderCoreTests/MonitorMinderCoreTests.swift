import Foundation
import Testing
@testable import MonitorMinderCore

private func display(_ key: String, x: Int, y: Int, w: Int = 2560, h: Int = 1440, hz: Double = 60, main: Bool = false) -> DisplayState {
    DisplayState(key: key, systemName: key, x: x, y: y, width: w, height: h,
                 pixelWidth: w * 2, pixelHeight: h * 2, refreshRate: hz, isMain: main)
}

@Test func identicalArrangementHasNoDrift() {
    let saved = [display("a", x: 0, y: 0, main: true), display("b", x: -2560, y: 0)]
    #expect(Drift.between(saved: saved, current: saved).isEmpty)
}

@Test func reportsMoveAndResolution() {
    let saved = [display("a", x: 0, y: 0, main: true), display("b", x: -2560, y: 0)]
    var b = display("b", x: -2568, y: 12, w: 1920, h: 1080)
    b.pixelWidth = 1920; b.pixelHeight = 1080
    let drift = Drift.between(saved: saved, current: [saved[0], b])
    #expect(drift == [.resized(key: "b", current: "1920 × 1080", saved: "2560 × 1440"), .moved(key: "b", dx: -8, dy: 12)])
}

@Test func reportsRefreshAndMissing() {
    let saved = [display("a", x: 0, y: 0, hz: 120, main: true), display("b", x: 2560, y: 0)]
    let drift = Drift.between(saved: saved, current: [display("a", x: 0, y: 0, hz: 60, main: true)])
    #expect(drift == [.refresh(key: "a", current: 60, saved: 120), .missing(key: "b")])
}

@Test func setupIgnoresOrderAndPosition() {
    let one = [display("a", x: 0, y: 0), display("b", x: 10, y: 0)]
    let two = [display("b", x: 99, y: 5), display("a", x: 0, y: 0)]
    #expect(SavedLayout.setup(of: one) == SavedLayout.setup(of: two))
}

@Test func placementRelativeToMain() {
    let main = display("a", x: 0, y: 0, main: true)
    #expect(display("b", x: -2560, y: 0).placement(relativeTo: main) == .left)
    #expect(display("b", x: 2560, y: 200).placement(relativeTo: main) == .right)
    #expect(display("b", x: 500, y: 1440, w: 1512, h: 982).placement(relativeTo: main) == .below)
    #expect(display("b", x: 0, y: -1440).placement(relativeTo: main) == .above)
}

@Test func snapsFlushToNearestEdge() {
    let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    // Dropped slightly overlapping the right side and a little low: lands flush, tops aligned.
    let dropped = CGRect(x: 2500, y: 40, width: 2560, height: 1440)
    #expect(Arrangement.snap(dropped, to: [main], alignWithin: 100) == CGPoint(x: 2560, y: 0))
    // Far away on the left: pulled in to touch.
    let far = CGRect(x: -4000, y: 300, width: 1920, height: 1080)
    #expect(Arrangement.snap(far, to: [main], alignWithin: 10) == CGPoint(x: -1920, y: 300))
    // Within range of the bottom edge: bottoms line up.
    #expect(Arrangement.snap(far, to: [main], alignWithin: 100) == CGPoint(x: -1920, y: 360))
}

@Test func snapNeverOverlapsOtherDisplays() {
    let a = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let b = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
    let dropped = CGRect(x: 2400, y: 100, width: 1512, height: 982)
    let landed = CGRect(origin: Arrangement.snap(dropped, to: [a, b], alignWithin: 50), size: dropped.size)
    #expect(a.intersection(landed).width * a.intersection(landed).height <= 0.5)
    #expect(b.intersection(landed).width * b.intersection(landed).height <= 0.5)
}

@Test func normalizingMovesMainToOrigin() {
    let displays = [display("a", x: 0, y: 0, main: true), display("b", x: -2560, y: 200)]
    let result = Arrangement.normalized(displays, main: "b")
    #expect(result.map { [$0.x, $0.y] } == [[2560, -200], [0, 0]])
    #expect(result.map(\.isMain) == [false, true])
}

@Test func windowMatchingPrefersTitlesThenOrder() {
    func w(_ title: String, _ index: Int) -> WindowState {
        WindowState(bundleID: "x", appName: "X", title: title, index: index, display: "a", x: 0, y: 0, width: 1, height: 1)
    }
    let saved = [w("Inbox", 0), w("Old tab", 1), w("Notes", 2)]
    let pairs = WindowState.match(saved: saved, openTitles: ["Notes", "New tab", "Inbox"])
    let byName = Dictionary(uniqueKeysWithValues: pairs.map { (saved[$0.0].title, $0.1) })
    #expect(byName == ["Inbox": 2, "Notes": 0, "Old tab": 1])
}

@Test func extraSavedWindowsAreIgnored() {
    let saved = (0..<3).map { WindowState(bundleID: "x", appName: "X", title: "", index: $0, display: "a", x: 0, y: 0, width: 1, height: 1) }
    #expect(WindowState.match(saved: saved, openTitles: ["one"]).count == 1)
}

@Test func configRoundTripsAndToleratesMissingFields() throws {
    var config = Config()
    config.displayNames = ["b": "LG Left"]
    config.layouts = [SavedLayout(name: "Desk", displays: [display("a", x: 0, y: 0, main: true)], windows: [])]
    config.autoRestore = false
    let decoded = try ConfigStore.decode(ConfigStore.encode(config))
    #expect(decoded.layouts.first?.name == "Desk")
    #expect(decoded.displayNames == config.displayNames)
    #expect(decoded.autoRestore == false)

    let sparse = try ConfigStore.decode(Data(#"{"layouts": []}"#.utf8))
    #expect(sparse.autoRestore == true)
}

@Test func storeWritesAndReadsFile() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "mm-\(UUID().uuidString)/config.json")
    let store = ConfigStore(url: url)
    #expect(try store.load() == Config())
    var config = Config()
    config.displayNames = ["k": "Name"]
    try store.save(config)
    #expect(try store.load() == config)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}
