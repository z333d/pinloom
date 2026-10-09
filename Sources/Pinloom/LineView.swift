import SwiftUI

enum Layout {
    static let panelHeight: CGFloat = 210
    static let ropeTop: CGFloat = 10
    static let spacing: CGFloat = 174
    static let cardWidth: CGFloat = 150
    static let pinAbove: CGFloat = 9.5

    /// The rope hangs as a parabola from edge to edge of the screen.
    static func sag(width: CGFloat) -> CGFloat { min(30, width * 0.018) }

    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = x / width
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }

    static func slotWidth(_ item: Pegged) -> CGFloat {
        max(cardWidth, PeggedView.cardSize(for: item.thumb.size, scale: item.scale).width + 20)
    }
    static func rowWidth(items: [Pegged]) -> CGFloat {
        items.reduce(0) { $0 + slotWidth($1) } + CGFloat(max(0, items.count - 1)) * 24
    }
    static func x(index: Int, items: [Pegged], width: CGFloat, trailingWidth: CGFloat = 0) -> CGFloat {
        let start = (width - rowWidth(items: items) - trailingWidth) / 2
        return start + items.prefix(index).reduce(0) { $0 + slotWidth($1) + 24 } + slotWidth(items[index]) / 2
    }
}

enum HangingLayout {
    static func position(for item: Pegged, index: Int, items: [Pegged], width: CGFloat, height: CGFloat, trailingWidth: CGFloat = 0) -> CGPoint {
        let card = PeggedView.cardSize(for: item.thumb.size, scale: item.scale)
        let halfWidth = card.width / 2 + 18
        let requestedX = item.hangingPosition?.x ?? Layout.x(index: index, items: items, width: width, trailingWidth: trailingWidth)
        let x = max(halfWidth, min(width - halfWidth, requestedX))
        let ropeTop = max(0, Layout.ropeY(x: x, width: width) - Layout.pinAbove)
        let requestedY = item.hangingPosition?.y ?? ropeTop
        let maxY = max(ropeTop, height - card.height - 40)
        return CGPoint(x: x, y: max(ropeTop, min(maxY, requestedY)))
    }
}

struct LineView: View {
    @ObservedObject var line: Line

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let rowWidth = max(width, line.contentWidth + 40)
            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal) {
                    ZStack(alignment: .topLeading) {
                        Rope(width: rowWidth)
                        ForEach(Array(line.items.enumerated()), id: \.element.id) { index, item in
                            let anchor = HangingLayout.position(for: item, index: index, items: line.items,
                                                                width: rowWidth, height: line.availableHeight, trailingWidth: line.notesWidth)
                            let ropeY = Layout.ropeY(x: anchor.x, width: rowWidth)
                            Path { path in
                                path.move(to: CGPoint(x: anchor.x, y: ropeY))
                                path.addLine(to: CGPoint(x: anchor.x, y: anchor.y + Layout.pinAbove))
                            }.stroke(Color(white: 0.55).opacity(0.6), lineWidth: 1).allowsHitTesting(false)
                            PeggedView(item: item, line: line, anchor: anchor)
                                .frame(width: Layout.slotWidth(item), height: max(1, geo.size.height - anchor.y), alignment: .top)
                                .position(x: anchor.x, y: anchor.y + max(1, geo.size.height - anchor.y) / 2)
                                .zIndex(line.frontmostItemID == item.id ? 100 : Double(index))
                        }
                        ForEach(Array(line.notes.enumerated()), id: \.element.id) { index, note in
                            let anchor = line.notePosition(note, index: index, width: rowWidth)
                            Path { path in
                                path.move(to: CGPoint(x: anchor.x, y: Layout.ropeY(x: anchor.x, width: rowWidth)))
                                path.addLine(to: CGPoint(x: anchor.x, y: anchor.y + Layout.pinAbove))
                            }.stroke(Color(white: 0.55).opacity(0.6), lineWidth: 1).allowsHitTesting(false)
                            StickyNoteCard(note: note, line: line, anchor: anchor)
                                .position(x: anchor.x, y: anchor.y + (line.noteSize(note).height + 14) / 2)
                                .zIndex(line.frontmostItemID == note.id ? 100 : Double(line.items.count + index))
                                .id(note.id)
                        }
                    }.frame(width: rowWidth, height: geo.size.height)
                }
                .scrollIndicators(.hidden)

                if line.totalCount == 0 {
                    ImportHint(line: line)
                        .position(x: width / 2, y: 98)
                        .transition(.opacity)
                }

                HStack(spacing: 6) {
                    ImportButton(line: line, action: .clipboard)
                    ImportButton(line: line, action: .files)
                    ImportButton(line: line, action: .note)
                    LineDismissButton(line: line)
                }
                    .frame(width: 418, height: 26)
                    .position(x: width / 2, y: 16)
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: line.items.map(\.id))
            .animation(.easeInOut(duration: 0.3), value: line.totalCount == 0)
            // Explicit show/hide actions slide the line under the menu bar.
            .offset(y: line.revealed ? 0 : -(geo.size.height + 12))
            .animation(line.revealed ? .spring(response: 0.42, dampingFraction: 0.82)
                                     : .easeIn(duration: 0.22), value: line.revealed)
        }
        .onPreferenceChange(HitRectsKey.self) { rects in
            line.hitRects = rects
        }
        .onPreferenceChange(ClipRectsKey.self) { line.clipRects = $0 }
    }
}

private struct LineDismissButton: View {
    @ObservedObject var line: Line
    var body: some View {
        Label(L("Hide line"), systemImage: "xmark")
            .font(.system(size: 11, weight: .medium))
            .frame(width: 100, height: 26).glassFrame(capsule: true)
            .overlay(LineDismissArea(line: line).frame(maxWidth: .infinity, maxHeight: .infinity))
            .help(L("Hide line"))
    }
}

private struct LineDismissArea: NSViewRepresentable {
    let line: Line
    func makeNSView(context: Context) -> LineDismissView { LineDismissView() }
    func updateNSView(_ view: LineDismissView, context: Context) { view.configure(line: line) }
}

final class LineDismissView: NSView {
    private var onClick: () -> Void = {}

    func configure(line: Line) {
        // Resolve the live callback: the app installs its actions after the
        // initial hosting view has already been created.
        onClick = { line.onHideLine() }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L("Hide line"))
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}

struct ClipRectsKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { _, new in new } }
}

private struct ImportButton: View {
    @ObservedObject var line: Line
    let action: LineImportAction
    var body: some View {
        Label(action.title, systemImage: action.symbol)
            .font(.system(size: 11, weight: .medium))
            .frame(width: 100, height: 26).glassFrame(capsule: true)
            .overlay(LineImportArea(line: line, action: action).frame(maxWidth: .infinity, maxHeight: .infinity))
    }
}

private struct ImportHint: View {
    @ObservedObject var line: Line
    var body: some View {
        VStack(spacing: 7) {
            Label(L("Drop images here"), systemImage: "photo.badge.plus")
                .font(.system(size: 12, weight: .medium, design: .rounded))
            Text(L("Or click to choose images"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(width: 312, height: 76).glassFrame(cornerRadius: Frame.radius)
        .overlay(RoundedRectangle(cornerRadius: Frame.radius)
            .strokeBorder(.primary.opacity(line.receivingDrop ? 0.5 : 0.12),
                          style: StrokeStyle(lineWidth: 1, dash: [4, 3])).allowsHitTesting(false))
        .overlay(LineImportArea(line: line, action: .files).frame(maxWidth: .infinity, maxHeight: .infinity))
    }
}

/// A thin, neutral line: a mid gray core with a faint highlight and a soft
/// shadow, so it reads on light and dark backgrounds alike. It fades out at
/// both ends so it seems to come from beyond the screen.
struct Rope: View {
    let width: CGFloat

    private var path: Path {
        Path { p in
            let top = Layout.ropeTop
            p.move(to: CGPoint(x: -20, y: top))
            p.addQuadCurve(
                to: CGPoint(x: width + 20, y: top),
                control: CGPoint(x: width / 2, y: top + 2 * Layout.sag(width: width)))
        }
    }

    var body: some View {
        ZStack {
            path.stroke(Color.black.opacity(0.22), lineWidth: 1.4).offset(y: 1.2).blur(radius: 1.2)
            path.stroke(Color(white: 0.55), lineWidth: 1.2)
            path.stroke(Color.white.opacity(0.45), lineWidth: 0.4).offset(y: -0.35)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .allowsHitTesting(false)
    }
}

struct HitRectsKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
