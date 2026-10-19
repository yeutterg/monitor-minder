import MonitorMinderCore
import SwiftUI

struct SettingsPage: View {
    let model: AppModel
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Settings", back: back)
            PageForm {
                Section {
                    Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 })) {
                        Label("Open at Login", systemImage: "power")
                    }
                    .toggleStyle(.switch)
                }

                Section {
                    if model.accessibilityTrusted {
                        Label {
                            TwoLine(title: "Window access allowed", subtitle: "Layouts can save and move windows")
                        } icon: { Image(systemName: "checkmark.circle").foregroundStyle(.green) }
                    } else {
                        Label {
                            VStack(alignment: .leading, spacing: 6) {
                                TwoLine(title: "Window access off", subtitle: "Needed only for layouts with windows")
                                Button("Open Settings") { model.requestAccessibility() }
                            }
                        } icon: { Image(systemName: "lock").foregroundStyle(.orange) }
                    }
                }

                Section {
                    Label {
                        TwoLine(title: "config.json", subtitle: abbreviated(model.store.url.deletingLastPathComponent()))
                    } icon: { Image(systemName: "doc.text") }
                    Button("Show in Finder") { model.revealConfig() }
                    Button("Export…") { model.exportConfig() }
                    Button("Import…") { model.importConfig() }
                } header: {
                    Text("Config")
                } footer: {
                    Text("All layouts and display names live in this one file. Importing replaces them. Deleting the app leaves the file; delete its folder to remove everything.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.link)
        }
        .task {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
