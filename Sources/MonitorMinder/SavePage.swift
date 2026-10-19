import MonitorMinderCore
import SwiftUI

/// Records the current arrangement (and optionally windows) as a named layout.
struct SavePage: View {
    let model: AppModel
    let done: () -> Void
    @State private var name = ""
    @State private var includeWindows = true
    @State private var names: [String: String] = [:]
    @State private var windowCount: Int?
    @FocusState private var nameFocused: Bool

    private var needsAccess: Bool { includeWindows && !model.accessibilityTrusted }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !needsAccess }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Save Layout", back: done)
            PageForm {
                Section {
                    TextField("Name", text: $name, prompt: Text("Desk"))
                        .focused($nameFocused)
                        .onSubmit { if canSave { commit() } }
                    Picker("Save", selection: $includeWindows) {
                        Text("Arrangement").tag(false)
                        Text("Arrangement + Windows").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("What gets saved") {
                    ForEach(model.displays) { d in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                TextField("Display name", text: binding(d.key), prompt: Text(d.systemName))
                                    .textFieldStyle(.plain)
                                    .labelsHidden()
                                    .multilineTextAlignment(.leading)
                                Text(model.detailText(d)).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "display") }
                    }
                    if includeWindows {
                        if needsAccess {
                            Label {
                                VStack(alignment: .leading, spacing: 6) {
                                    TwoLine(title: "Allow window access",
                                            subtitle: "Turn on Monitor Minder in Privacy & Security › Accessibility")
                                    Button("Open Settings") { model.requestAccessibility() }
                                }
                            } icon: { Image(systemName: "lock").foregroundStyle(.orange) }
                        } else {
                            Label {
                                TwoLine(title: windowCount.map { "\($0) window\($0 == 1 ? "" : "s")" } ?? "Windows",
                                        subtitle: "On this Space; full-screen windows are skipped")
                            } icon: { Image(systemName: "macwindow.on.rectangle") }
                        }
                    }
                }

                Section {
                    HStack {
                        Label("Shortcut", systemImage: "keyboard")
                        Spacer()
                        Text(model.layouts.count < 9 ? "⌃⌥\(model.layouts.count + 1)" : "None").foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Button("Cancel", action: done)
                            .frame(maxWidth: .infinity)
                        Button("Save", action: commit)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canSave)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
            }
        }
        .onAppear {
            names = model.config.displayNames
            name = model.layouts.isEmpty ? "Desk" : ""
            nameFocused = true
        }
        // Notice when Accessibility access is granted, and keep the window count fresh.
        .task {
            while !Task.isCancelled {
                model.refresh()
                if model.accessibilityTrusted { windowCount = model.windowCount() }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { names[key] ?? "" }, set: { names[key] = $0 })
    }

    private func commit() {
        model.saveCurrent(name: name, includeWindows: includeWindows, displayNames: names)
        done()
    }
}
