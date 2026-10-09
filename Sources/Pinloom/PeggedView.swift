import SwiftUI

/// One photo with its clothespin. All the charm lives here: it drops onto
/// the line, swings, sways with the breeze and falls when you pull it off.
struct PeggedView: View {
    let item: Pegged
    @ObservedObject var line: Line
    let anchor: CGPoint

    @State private var swing: Double = 0
    @State private var arrived = false
    @State private var hovering = false
    @StateObject private var motion = HangingMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var copied: Bool { line.copiedID == item.id }
    private var dragging: Bool { line.draggingID == item.id }
    private var pressed: Bool { line.pressedID == item.id }

    var body: some View {
        VStack(spacing: -12) {
            Clothespin()
                .frame(width: 32, height: 26)
                .overlay(ClipMoveArea(item: item, line: line, anchor: anchor, motion: motion, reduceMotion: reduceMotion))
                .help(L("Drag this clip to move only this image. Right-click to reset its position."))
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ClipRectsKey.self,
                                           value: item.falling ? [:] : [item.id: geometry.frame(in: .global)])
                })
                .zIndex(1)
            card
        }
        .rotationEffect(.degrees(swing + item.tilt + motion.degrees), anchor: .top)
        .offset(y: arrived ? 0 : -46)
        // The fall itself is drawn over the whole screen by FallingCard, so
        // the card here just steps aside at once.
        .opacity(item.falling ? 0 : (arrived ? 1 : 0))
        .transaction { t in if item.falling { t.animation = nil } }
        .onAppear(perform: arrive)
        .onDisappear { motion.stop() }
        .onChange(of: reduceMotion) { _, reduced in if reduced { motion.stop() } }
        .onChange(of: line.gust) { _, _ in breeze() }
        .onChange(of: copied) { _, isCopied in if isCopied { nudge(3) } }
    }

    /// The photo fits inside the card area keeping its proportions, so the
    /// white border hugs it whether the screenshot is wide or tall.
    static func photoSize(for size: CGSize, scale cardScale: CGFloat = 1) -> CGSize {
        let maxW = (Layout.cardWidth - 14) * cardScale, maxH: CGFloat = 104 * cardScale
        guard size.width > 0, size.height > 0 else { return CGSize(width: maxW, height: maxH) }
        let scale = min(maxW / size.width, maxH / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// The card around the photo: the photo plus the glass inset.
    static func cardSize(for size: CGSize, scale: CGFloat = 1) -> CGSize {
        let p = photoSize(for: size, scale: scale)
        return CGSize(width: max(64, p.width) + Frame.inset * 2, height: max(40, p.height) + Frame.inset * 2)
    }

    private var photoSize: CGSize { Self.photoSize(for: item.thumb.size, scale: item.scale) }

    private var card: some View {
        Image(nsImage: item.thumb)
            .resizable()
            .interpolation(.high)
            .frame(width: photoSize.width, height: photoSize.height)
            .frame(minWidth: 64, minHeight: 40)
            // Concentric corners: the photo's radius is the frame's minus the
            // inset, the way macOS rounds nested shapes.
            .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .padding(Frame.inset)
            .glassFrame(cornerRadius: Frame.radius)
            .shadow(color: .black.opacity(hovering ? 0.26 : 0.18), radius: hovering ? 14 : 10, y: hovering ? 8 : 5)
            // Holding presses the photo in slowly, so a long press feels like
            // it is building up to something.
            .scaleEffect(pressed ? 0.95 : (hovering ? 1.035 : 1), anchor: .top)
            .animation(pressed ? .easeInOut(duration: 0.45) : .spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .opacity(dragging ? 0.45 : 1)
            .overlay(alignment: .topLeading) {
                // Drawn here, clicked through GrabView, which sits on top.
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .glassFrame(circle: true)
                    .padding(3)
                    .opacity(hovering && !dragging ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
                    .allowsHitTesting(false)
            }
            .overlay(GrabArea(item: item, line: line))
            .overlay(alignment: .topTrailing) {
                Image(systemName: line.isPinned(item) ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .glassFrame(circle: true).padding(3)
                    .opacity((hovering || line.isPinned(item)) && !dragging ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22).glassFrame(circle: true).padding(3)
                    .opacity(dragging ? 0 : (hovering || line.resizingID == item.id ? 1 : 0.5))
                    .allowsHitTesting(false)
            }
            .help(L("Click to copy. Double-click to preview. Use the pin to keep a reference image visible."))
            .overlay(alignment: .bottom) {
                if copied {
                    Label(L("Copied"), systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassFrame(capsule: true)
                        .offset(y: 16)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: hovering)
            .animation(.easeOut(duration: 0.2), value: copied)
            .onHover { hovering = $0 }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self,
                                           value: item.falling ? [:] : [item.id: g.frame(in: .global)])
                }
            )
    }

    private func arrive() {
        swing = 16
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { arrived = true }
        withAnimation(.interpolatingSpring(stiffness: 46, damping: 2.6)) { swing = 0 }
    }

    private func breeze() {
        guard line.movingItemID != item.id, line.resizingID != item.id else { return }
        let delay = Double.random(in: 0...0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            nudge(Double.random(in: 1.6...3.4))
        }
    }

    private func nudge(_ degrees: Double) {
        withAnimation(.easeOut(duration: 0.3)) { swing = degrees }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.interpolatingSpring(stiffness: 38, damping: 2.4)) { swing = 0 }
        }
    }
}

private struct ClipMoveArea: NSViewRepresentable {
    let item: Pegged
    let line: Line
    let anchor: CGPoint
    let motion: HangingMotion
    let reduceMotion: Bool
    func makeNSView(context: Context) -> ClipMoveView { ClipMoveView() }
    func updateNSView(_ view: ClipMoveView, context: Context) {
        view.anchor = anchor
        view.onMove = { point in
            line.move(item.id, to: point)
            if !reduceMotion, let actual = line.items.first(where: { $0.id == item.id })?.hangingPosition {
                motion.move(to: actual)
            }
        }
        view.onMoveState = { moving in
            line.movingItemID = moving ? item.id : nil
            if moving {
                line.frontmostItemID = item.id
                if !reduceMotion { motion.begin(at: anchor, length: PeggedView.cardSize(for: item.thumb.size, scale: item.scale).height / 2) }
            } else {
                motion.release()
            }
        }
        view.onReset = { line.resetPosition(item.id) }
    }
}

final class ClipMoveView: NSView {
    var anchor: CGPoint = .zero
    var onMove: (CGPoint) -> Void = { _ in }
    var onMoveState: (Bool) -> Void = { _ in }
    var onReset: () -> Void = {}
    var resetTitle = L("Reset image position")
    private var start: (mouse: NSPoint, anchor: CGPoint)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        start = (NSEvent.mouseLocation, anchor)
        onMoveState(true)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let mouse = NSEvent.mouseLocation
        onMove(CGPoint(x: start.anchor.x + mouse.x - start.mouse.x,
                       y: start.anchor.y - mouse.y + start.mouse.y))
    }
    override func mouseUp(with event: NSEvent) { start = nil; onMoveState(false) }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(resetTitle, handler: onReset))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

enum Frame {
    static let radius: CGFloat = 16
    static let inset: CGFloat = 4
}

extension View {
    /// A crisp glass: the system's blurred material with a thin specular
    /// edge, lit from above. No refraction, so the background stays sharp
    /// around the frame instead of bending like gel.
    func glassFrame(cornerRadius: CGFloat = 0, circle: Bool = false, capsule: Bool = false) -> some View {
        let shape: AnyShape = circle ? AnyShape(Circle())
            : capsule ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        return background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.stroke(
                    LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
            .overlay(shape.stroke(Color.black.opacity(0.10), lineWidth: 0.5).padding(-0.5))
    }
}

/// A minimal aluminium clip: a brushed metal pill with a slot where it
/// grips the line, and a soft shadow so it reads on any background.
struct Clothespin: View {
    private let metal = LinearGradient(
        stops: [
            .init(color: Color(white: 0.70), location: 0),
            .init(color: Color(white: 0.93), location: 0.35),
            .init(color: Color(white: 0.82), location: 0.65),
            .init(color: Color(white: 0.62), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(metal)
            .frame(width: 9, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.9), Color.black.opacity(0.18)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.6)
            )
            .overlay(alignment: .top) {
                // The slot the line passes through.
                Capsule()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 5, height: 1.4)
                    .padding(.top, 8.5)
            }
            .shadow(color: .black.opacity(0.30), radius: 2, y: 1.5)
            .allowsHitTesting(false)
    }
}
