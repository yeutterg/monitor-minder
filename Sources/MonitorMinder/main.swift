import AppKit
import MonitorMinderCore
import SwiftUI

/// Owns the long-lived model. One instance for the app's lifetime.
@MainActor
final class AppState {
    static let shared = AppState()
    let model = AppModel()
}

struct MonitorMinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            RootView(model: AppState.shared.model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            AppState.shared.model.start()
            // `--preview` shows the popover content in a normal window, for screenshots and development.
            if CommandLine.arguments.contains("--preview") { showPreview() }
            // `--open-menu` opens the real menu bar window once launched, for README screenshots.
            if CommandLine.arguments.contains("--open-menu") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Self.statusButton()?.performClick(nil) }
            }
        }
    }

    @MainActor private static func statusButton() -> NSStatusBarButton? {
        func find(_ view: NSView?) -> NSStatusBarButton? {
            guard let view else { return nil }
            if let button = view as? NSStatusBarButton { return button }
            return view.subviews.lazy.compactMap(find).first
        }
        return NSApp.windows.lazy.compactMap { find($0.contentView) }.first
    }

    @MainActor private func showPreview() {
        // `--page save|settings` opens the preview on a specific page.
        let page = CommandLine.arguments.firstIndex(of: "--page").flatMap { i in
            i + 1 < CommandLine.arguments.count ? Page(rawValue: CommandLine.arguments[i + 1]) : nil
        } ?? .main
        let host = NSHostingView(rootView: RootView(model: AppState.shared.model, page: page))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = "Monitor Minder Preview"
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        previewWindow = window

        // `--snapshot <path.png>`: write the preview to disk after it settles (development aid).
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                if CommandLine.arguments.contains("--quit") { NSApp.terminate(nil) }
            }
        }
    }
}

if CommandLine.arguments.contains("--dump") {
    // Development aid: print the connected displays as they would be saved.
    MainActor.assumeIsolated {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try! encoder.encode(Displays.current()), as: UTF8.self))
    }
} else {
    MonitorMinderApp.main()
}
