import SwiftUI

enum Page: String { case main, save, settings }

/// The menu bar window: native grouped forms with a push transition between pages.
struct RootView: View {
    let model: AppModel
    @State var page: Page = .main

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case .main:
                    MainPage(model: model, save: { page = .save }, settings: { page = .settings })
                        .transition(.push(from: .leading))
                case .save:
                    SavePage(model: model, done: { page = .main })
                        .transition(.push(from: .trailing))
                case .settings:
                    SettingsPage(model: model, back: { page = .main })
                        .transition(.push(from: .trailing))
                }
            }
            .animation(.smooth(duration: 0.3), value: page)
        }
        .frame(width: 320)
        .onAppear { model.refresh() }
        .onDisappear { page = .main }
    }
}

/// A grouped form that sizes itself to its content, so the menu bar window fits each page.
struct PageForm<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 200

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, new in
                guard new > 0, abs(new - height) > 0.5 else { return }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { height = new }
            }
            .frame(height: height)
    }
}

/// Back button and title for drill-down pages.
struct PageHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack {
            Button(action: back) {
                Label("Back", systemImage: "chevron.backward")
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .controlSize(.large)
            .help("Back")
            Text(title).font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

/// A form row that behaves like a navigation link.
struct DisclosureRow: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary).imageScale(.small)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Title with a smaller secondary line, as in System Settings rows.
struct TwoLine: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}
