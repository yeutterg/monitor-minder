import MonitorMinderCore
import SwiftUI

/// The displays drawn to scale, like the arrangement view in System Settings. Displays that
/// drifted are tinted orange, with their saved position as a dashed outline. Drag a display to
/// rearrange (it snaps flush to a neighbour on release); click one to rename it.
struct ArrangementDiagram: View {
    let model: AppModel
    @Binding var selection: String?
    @State private var dragging: String?
    @State private var dragOffset: CGSize = .zero

    private let box = CGSize(width: 264, height: 110)

    var body: some View {
        let shown = model.displays.filter { $0.mirrorOf == nil }
        let drift = model.drift
        let drifted = Set(drift.map(\.key))
        let movedKeys = Set(drift.compactMap { if case .moved(let key, _, _) = $0 { key } else { nil } })
        let ghosts = model.activeLayout?.displays.filter { movedKeys.contains($0.key) } ?? []
        let frames = (shown + ghosts).map(\.frame)
        let bounds = frames.dropFirst().reduce(frames.first ?? .zero) { $0.union($1) }
        let scale = min(box.width / max(bounds.width, 1), box.height / max(bounds.height, 1))
        let place: (CGRect) -> CGRect = { r in
            CGRect(x: (r.minX - bounds.minX) * scale, y: (r.minY - bounds.minY) * scale,
                   width: r.width * scale, height: r.height * scale).insetBy(dx: 0.75, dy: 0.75)
        }

        ZStack(alignment: .topLeading) {
            ForEach(ghosts) { g in
                let r = place(g.frame)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            ForEach(shown) { d in
                let r = place(d.frame)
                let isDragging = dragging == d.key
                Tile(name: model.name(d), detail: d.sizeText, isMain: d.isMain,
                     warning: drifted.contains(d.key), selected: selection == d.key || isDragging)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX + (isDragging ? dragOffset.width : 0),
                            y: r.minY + (isDragging ? dragOffset.height : 0))
                    .zIndex(isDragging ? 1 : 0)
                    .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: 6, y: 2)
                    .onTapGesture { selection = selection == d.key ? nil : d.key }
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            dragging = d.key
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            drop(d, translation: value.translation, scale: scale, among: shown)
                        })
                    .contextMenu {
                        Button("Make Main Display") { model.makeMain(d.key) }.disabled(d.isMain)
                        Button("Rename…") { selection = d.key }
                    }
                    .help("Drag to rearrange · click to rename")
            }
        }
        .frame(width: bounds.width * scale, height: bounds.height * scale, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    /// Converts the drag back to points, snaps it against the other displays and applies it.
    private func drop(_ d: DisplayState, translation: CGSize, scale: CGFloat, among shown: [DisplayState]) {
        let moved = d.frame.offsetBy(dx: translation.width / scale, dy: translation.height / scale)
        let others = shown.filter { $0.key != d.key }.map(\.frame)
        // Edges within ~6 px on screen line up, whatever the diagram's scale.
        let origin = Arrangement.snap(moved, to: others, alignWithin: 6 / scale)
        withAnimation(.smooth(duration: 0.2)) {
            if origin != d.frame.origin { model.move(d.key, to: origin) }
            dragging = nil
            dragOffset = .zero
        }
    }
}

private struct Tile: View {
    let name: String
    let detail: String
    let isMain: Bool
    let warning: Bool
    let selected: Bool

    var body: some View {
        let tint: Color = selected ? .accentColor : warning ? .orange : .primary
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        shape
            .fill(tint.opacity(selected || warning ? 0.16 : 0.07))
            .overlay(alignment: .top) {
                if isMain {
                    Rectangle().fill(.primary.opacity(0.22)).frame(height: 4)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(tint.opacity(selected || warning ? 0.9 : 0.3), lineWidth: 1))
            .overlay {
                VStack(spacing: 1) {
                    Text(name).font(.system(size: 10, weight: .semibold))
                    Text(detail).font(.system(size: 9)).foregroundStyle(warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(3)
            }
            .contentShape(shape)
    }
}
