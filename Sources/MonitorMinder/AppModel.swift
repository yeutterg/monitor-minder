import AppKit
import MonitorMinderCore
import Observation
import ServiceManagement

/// App state: the connected displays, the config, and how the two compare.
@MainActor @Observable
final class AppModel {
    private(set) var displays: [DisplayState] = []
    private(set) var config = Config()
    /// A short confirmation shown under the layouts, cleared after a few seconds.
    private(set) var status: String?
    private(set) var accessibilityTrusted = Windows.trusted

    let store = ConfigStore()
    private var pendingChange: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    /// Our own display changes fire the same notifications; don't react to them.
    private var quietUntil = Date.distantPast
    private var sawWake = false

    // MARK: Derived

    var setup: String { SavedLayout.setup(of: displays) }
    var layouts: [SavedLayout] { config.layouts(for: setup) }

    /// What drift is measured against: the layout last used with these displays, else the first one.
    var activeLayout: SavedLayout? {
        let all = layouts
        if let id = config.lastUsed[setup], let layout = all.first(where: { $0.id == id }) { return layout }
        return all.first
    }

    var drift: [Drift] {
        guard let layout = activeLayout else { return [] }
        return Drift.between(saved: layout.displays, current: displays)
    }

    func matches(_ layout: SavedLayout) -> Bool { Drift.between(saved: layout.displays, current: displays).isEmpty }

    func name(_ key: String) -> String {
        if let n = config.displayNames[key], !n.isEmpty { return n }
        return displays.first { $0.key == key }?.systemName
            ?? config.layouts.lazy.flatMap(\.displays).first { $0.key == key }?.systemName
            ?? "Display"
    }

    func name(_ display: DisplayState) -> String { name(display.key) }

    /// ⌃⌥1…9 follow the order of the layouts for the connected displays.
    func shortcut(for layout: SavedLayout) -> String? {
        guard let i = layouts.firstIndex(where: { $0.id == layout.id }), i < 9 else { return nil }
        return "⌃⌥\(i + 1)"
    }

    var mainDisplay: DisplayState? { displays.first(where: \.isMain) ?? displays.first }

    func placementText(_ d: DisplayState) -> String {
        guard let main = mainDisplay else { return "" }
        let other = name(main)
        switch d.placement(relativeTo: main) {
        case .main: return "Main display"
        case .mirroring: return "Mirroring \(d.mirrorOf.map(name) ?? "")"
        case .left: return "Left of \(other)"
        case .right: return "Right of \(other)"
        case .above: return "Above \(other)"
        case .below: return "Below \(other)"
        }
    }

    func detailText(_ d: DisplayState) -> String {
        [d.sizeText, d.refreshRate > 0 ? "\(d.refreshHz) Hz" : nil, placementText(d)].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Lifecycle

    func start() {
        do { config = try store.load() } catch { flash("Couldn't read config: \(error.localizedDescription)") }
        refresh()
        DisplayWatcher.start { [weak self] in self?.displaysChanged() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    AppState.shared.model.sawWake = true
                    AppState.shared.model.displaysChanged()
                }
            }
        }
        Hotkeys.register { [weak self] n in
            guard let self, n - 1 < self.layouts.count else { return }
            self.apply(self.layouts[n - 1])
        }
    }

    func refresh() {
        displays = Displays.current()
        accessibilityTrusted = Windows.trusted
    }

    /// Display changes arrive in bursts while macOS settles; act once it's quiet.
    private func displaysChanged() {
        pendingChange?.cancel()
        pendingChange = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let before = setup
            refresh()
            let woke = sawWake
            sawWake = false
            // Only connects and wakes trigger a restore; a change made on purpose in System
            // Settings just shows as drift.
            guard config.autoRestore, Date() > quietUntil, woke || setup != before,
                  let layout = activeLayout, !drift.isEmpty else { return }
            apply(layout, automatic: true)
        }
    }

    // MARK: Actions

    func apply(_ layout: SavedLayout, automatic: Bool = false) {
        quietUntil = Date() + 6
        let notes = Displays.apply(layout.displays)
        config.lastUsed[layout.setup] = layout.id
        persist()
        Task {
            // Windows can only move onto displays once macOS has finished rearranging them.
            try? await Task.sleep(for: .seconds(1.2))
            refresh()
            var moved = 0
            if let windows = layout.windows { moved = Windows.restore(windows, on: displays) }
            var message = "\(automatic ? "Auto-restored" : "Restored") “\(layout.name)”"
            if moved > 0 { message += " · moved \(moved) window\(moved == 1 ? "" : "s")" }
            if let note = notes.first { message = note }
            flash(message)
            quietUntil = Date() + 2
        }
    }

    func saveCurrent(name: String, includeWindows: Bool, displayNames: [String: String]) {
        refresh()
        for (key, value) in displayNames {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            config.displayNames[key] = trimmed.isEmpty ? nil : trimmed
        }
        let windows = includeWindows ? Windows.capture(on: displays) : nil
        let layout = SavedLayout(name: name.trimmingCharacters(in: .whitespaces), displays: displays, windows: windows)
        config.layouts.append(layout)
        config.lastUsed[layout.setup] = layout.id
        persist()
        flash("Saved “\(layout.name)”")
    }

    func update(_ layout: SavedLayout) {
        guard let i = config.layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        refresh()
        config.layouts[i].displays = displays
        if layout.windows != nil { config.layouts[i].windows = Windows.capture(on: displays) }
        config.lastUsed[layout.setup] = layout.id
        persist()
        flash("Updated “\(layout.name)”")
    }

    func delete(_ layout: SavedLayout) {
        config.layouts.removeAll { $0.id == layout.id }
        if config.lastUsed[layout.setup] == layout.id { config.lastUsed[layout.setup] = nil }
        persist()
    }

    func rename(display key: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        config.displayNames[key] = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    /// Moves one display (from the diagram) and applies the arrangement right away.
    func move(_ key: String, to origin: CGPoint) {
        guard let i = displays.firstIndex(where: { $0.key == key }), let main = mainDisplay else { return }
        var target = displays
        target[i].x = Int(origin.x)
        target[i].y = Int(origin.y)
        rearrange(Arrangement.normalized(target, main: main.key))
    }

    func makeMain(_ key: String) {
        rearrange(Arrangement.normalized(displays, main: key))
    }

    private func rearrange(_ target: [DisplayState]) {
        quietUntil = Date() + 4
        // Show the result immediately; the refresh below confirms where macOS actually put it.
        displays = target
        let notes = Displays.apply(target)
        if let note = notes.first { flash(note) }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            refresh()
        }
    }

    var autoRestore: Bool {
        get { config.autoRestore }
        set { config.autoRestore = newValue; persist() }
    }

    func windowCount() -> Int { Windows.capture(on: displays).count }

    // MARK: Config file

    func revealConfig() {
        persist()
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Monitor Minder Config.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ConfigStore.encode(config).write(to: url, options: .atomic); flash("Exported config") }
        catch { flash("Export failed: \(error.localizedDescription)") }
    }

    func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            config = try ConfigStore.decode(Data(contentsOf: url))
            persist()
            flash("Imported \(config.layouts.count) layout\(config.layouts.count == 1 ? "" : "s")")
        } catch { flash("That file isn't a Monitor Minder config") }
    }

    private func persist() {
        do { try store.save(config) } catch { flash("Couldn't save config: \(error.localizedDescription)") }
    }

    private func flash(_ message: String) {
        status = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { status = nil }
        }
    }

    // MARK: Permissions and login

    func requestAccessibility() {
        Windows.requestAccess()
        NSWorkspace.shared.open(Windows.settingsURL)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { flash("Couldn't change Open at Login: \(error.localizedDescription)") }
        }
    }
}

/// Forwards Quartz display reconfiguration callbacks to the main actor.
@MainActor
enum DisplayWatcher {
    private static var action: (() -> Void)?

    static func start(_ action: @escaping () -> Void) {
        self.action = action
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            if flags.contains(.beginConfigurationFlag) { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { DisplayWatcher.action?() } }
        }, nil)
    }
}
