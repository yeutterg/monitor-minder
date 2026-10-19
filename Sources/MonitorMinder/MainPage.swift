import MonitorMinderCore
import SwiftUI

struct MainPage: View {
    let model: AppModel
    let save: () -> Void
    let settings: () -> Void
    @State private var selection: String?
    @State private var draftName = ""

    var body: some View {
        PageForm {
            Section {
                ArrangementDiagram(model: model, selection: $selection)
                if let key = selection {
                    TextField("Name", text: $draftName, prompt: Text(model.displays.first { $0.key == key }?.systemName ?? ""))
                        .onSubmit { model.rename(display: key, to: draftName); selection = nil }
                }
            } header: {
                HStack(spacing: 7) {
                    Image(nsImage: MenuBarIcon.image)
                    Text("Monitor Minder")
                }
            } footer: {
                Text(selection == nil ? "Drag to rearrange · click to rename" : "Press Return to save the name")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .onChange(of: selection) { _, key in draftName = key.map { model.config.displayNames[$0] ?? "" } ?? "" }

            if let layout = model.activeLayout, !model.drift.isEmpty {
                DriftSection(model: model, layout: layout)
            }

            Section {
                ForEach(model.layouts) { layout in
                    LayoutRow(model: model, layout: layout)
                }
                Button(action: save) {
                    Label("Save Current Layout…", systemImage: "plus")
                        .foregroundStyle(.tint)
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } header: {
                Text(model.layouts.isEmpty ? "No layouts for these displays yet" : "Layouts for these displays")
            } footer: {
                if let status = model.status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(isOn: Binding(get: { model.autoRestore }, set: { model.autoRestore = $0 })) {
                    Label { TwoLine(title: "Auto-restore", subtitle: "When these displays connect or wake") }
                        icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                }
                .toggleStyle(.switch)
            }

            Section {
                DisclosureRow(title: "Settings", systemImage: "gearshape", action: settings)
                Button { NSApp.terminate(nil) } label: {
                    HStack {
                        Label("Quit Monitor Minder", systemImage: "power")
                        Spacer()
                        Text("⌘Q").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
        }
    }
}

/// What changed since the active layout was saved, and one button to put it back.
private struct DriftSection: View {
    let model: AppModel
    let layout: SavedLayout

    var body: some View {
        Section {
            ForEach(Array(model.drift.enumerated()), id: \.offset) { _, drift in
                Label { TwoLine(title: title(drift), subtitle: subtitle(drift)) }
                    icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            VStack(spacing: 6) {
                Button { model.apply(layout) } label: {
                    HStack(spacing: 8) {
                        Text("Snap Back to “\(layout.name)”").fontWeight(.semibold)
                        if let shortcut = model.shortcut(for: layout) { Text(shortcut).foregroundStyle(.white.opacity(0.7)) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text(layout.windows.map { "Restores position, resolution and \($0.count) windows" } ?? "Restores position and resolution")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
    }

    private func title(_ drift: Drift) -> String {
        let name = model.name(drift.key)
        switch drift {
        case .moved(_, let dx, let dy):
            let parts = [dx == 0 ? nil : "\(abs(dx)) pt \(dx < 0 ? "left" : "right")",
                         dy == 0 ? nil : "\(abs(dy)) pt \(dy < 0 ? "up" : "down")"].compactMap { $0 }
            return "\(name) moved \(parts.joined(separator: ", "))"
        case .resized(_, let current, _): return "\(name) is \(current)"
        case .refresh(_, let current, _): return "\(name) is at \(current) Hz"
        case .mirroring: return "\(name) mirroring changed"
        case .missing: return "\(name) isn't connected"
        }
    }

    private func subtitle(_ drift: Drift) -> String {
        switch drift {
        case .moved: "The pointer may not cross where displays meet"
        case .resized(_, _, let saved): "Saved at \(saved)"
        case .refresh(_, _, let saved): "Saved at \(saved) Hz"
        case .mirroring, .missing: "Different from when it was saved"
        }
    }
}

private struct LayoutRow: View {
    let model: AppModel
    let layout: SavedLayout
    @State private var confirmDelete = false

    var body: some View {
        HStack {
            Button { model.apply(layout) } label: {
                HStack {
                    Label {
                        TwoLine(title: layout.name,
                                subtitle: layout.windows.map { "Arrangement + \($0.count) windows" } ?? "Arrangement only")
                    } icon: {
                        Image(systemName: layout.windows == nil ? "rectangle.3.group" : "macwindow.on.rectangle")
                    }
                    Spacer()
                    if model.matches(layout) {
                        Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                    } else if let shortcut = model.shortcut(for: layout) {
                        Text(shortcut).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Apply this layout")

            Menu {
                Button("Update to Current Arrangement") { model.update(layout) }
                Divider()
                Button("Delete…", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
        .confirmationDialog("Delete “\(layout.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.delete(layout) }
        }
    }
}
