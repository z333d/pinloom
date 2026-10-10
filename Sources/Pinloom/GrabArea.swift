import AppKit
import SwiftUI

/// Bridges each photo to AppKit's drag and drop, so it can be dragged into
/// any app as a real file. Each destination means one thing:
///
/// - An app gets a copy, and the photo stays on the line.
/// - A folder or the Desktop gets a copy; the original stays put.
/// - The Trash discards it.
/// - Nowhere that accepts it: the photo flies back to the line.
///
/// Click copies, press and hold opens Markup, the corner cross discards.
struct GrabArea: NSViewRepresentable {
    let item: Pegged
    let line: Line

    func makeNSView(context: Context) -> GrabView {
        let view = GrabView()
        configure(view)
        return view
    }

    func updateNSView(_ view: GrabView, context: Context) {
        configure(view)
    }

    private func configure(_ view: GrabView) {
        let id = item.id
        let line = line
        view.url = item.url
        view.dragImage = item.thumb
        view.onClick = { line.copy(id) }
        view.onDoubleClick = { line.preview(id) }
        view.onPin = { line.pin(id) }
        view.cardScale = item.scale
        view.toolTip = L("Drag the bottom-right corner to resize this image on the line.")
        view.onResize = { scale in line.resize(id, scale: scale) }
        view.onResizeState = { resizing in line.resizingID = resizing ? id : nil }
        view.onDragStart = { line.draggingID = id }
        view.onDragEnd = {
            line.draggingID = nil
            // Only explicit deletion can remove the original after a drag.
            line.prune()
        }
        view.onTrash = { line.trash(id) }
        view.onDiscard = { line.discard(id) }
        view.onLongPress = { line.markup(id) }
        view.onPressChange = { pressed in line.pressedID = pressed ? id : nil }
        view.menuProvider = {
            let menu = NSMenu()
            menu.addItem(ClosureMenuItem(L("Copy")) { line.copy(id) })
            menu.addItem(ClosureMenuItem(L("Preview")) { line.preview(id) })
            menu.addItem(ClosureMenuItem(L("Pin reference image")) { line.pin(id) })
            menu.addItem(ClosureMenuItem(L("Open in default app")) { line.open(id) })
            menu.addItem(ClosureMenuItem(L("Markup")) { line.markup(id) })
            menu.addItem(ClosureMenuItem(L("Show in Finder")) { line.reveal(id) })
            menu.addItem(ClosureMenuItem(L("Copy to Desktop")) { line.copyToDesktop(id) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(L("Larger on line")) { line.resize(id, scale: item.scale * 1.25) })
            menu.addItem(ClosureMenuItem(L("Smaller on line")) { line.resize(id, scale: item.scale / 1.25) })
            menu.addItem(ClosureMenuItem(L("Reset image size")) { line.resize(id, scale: CardSizing.defaultImageScale) })
            menu.addItem(ClosureMenuItem(L("Reset image position")) { line.resetPosition(id) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(L("Take down")) { line.discard(id) })
            menu.addItem(ClosureMenuItem(L("Move to Trash")) { line.trash(id) })
            return menu
        }
    }
}

final class GrabView: NSView, NSDraggingSource {
    static var isDragging = false

    var url: URL?
    var dragImage: NSImage?
    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onPin: () -> Void = {}
    var cardScale: CGFloat = 1
    var onResize: (CGFloat) -> Void = { _ in }
    var onResizeState: (Bool) -> Void = { _ in }
    private var resizeStart: (point: NSPoint, size: NSSize, scale: CGFloat)?
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onTrash: () -> Void = {}
    var onDiscard: () -> Void = {}
    var onLongPress: () -> Void = {}
    var onPressChange: (Bool) -> Void = { _ in }
    var menuProvider: () -> NSMenu = { NSMenu() }

    private var downPoint: NSPoint?
    private var startedDrag = false
    private var holdTimer: Timer?
    private var didLongPress = false
    private var pointerTrackingArea: NSTrackingArea?

    /// How long you hold before Markup opens. Long enough not to fire on a
    /// slow click, short enough to feel deliberate.
    private static let holdDuration: TimeInterval = 0.45

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func resizeRect(in bounds: NSRect, flipped: Bool) -> NSRect {
        let height = min(crossHitSize, max(0, bounds.height - crossHitSize))
        return NSRect(x: bounds.maxX - crossHitSize,
                      y: flipped ? bounds.maxY - height : bounds.minY,
                      width: min(crossHitSize, bounds.width), height: height)
    }

    static let resizeCursor: NSCursor = {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .bottomRight, directions: .all)
        }
        // Sonoma has no public diagonal frame cursor. Use the same arrow
        // direction with a white outline so it reads on any screenshot.
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 5, y: 19)); path.line(to: NSPoint(x: 19, y: 5))
            path.move(to: NSPoint(x: 5, y: 12)); path.line(to: NSPoint(x: 5, y: 19)); path.line(to: NSPoint(x: 12, y: 19))
            path.move(to: NSPoint(x: 12, y: 5)); path.line(to: NSPoint(x: 19, y: 5)); path.line(to: NSPoint(x: 19, y: 12))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()

    override func resetCursorRects() {
        addCursorRect(Self.resizeRect(in: bounds, flipped: isFlipped), cursor: Self.resizeCursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        // The line never becomes key. activeAlways delivers hover events
        // even while the user works in another app; cursorUpdate doesn't.
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    func cursor(at point: NSPoint) -> NSCursor {
        resizeStart != nil || Self.resizeRect(in: bounds, flipped: isFlipped).contains(point)
            ? Self.resizeCursor : .arrow
    }

    func updatePointer(at point: NSPoint) { cursor(at: point).set() }

    override func mouseEntered(with event: NSEvent) {
        updatePointer(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        if resizeStart == nil { NSCursor.arrow.set() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    /// The discard cross drawn in the top left corner of the card. It is
    /// handled here because this view sits on top of the SwiftUI card.
    static let crossHitSize: CGFloat = 26

    private func isInCross(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        let corner = NSRect(x: 0, y: isFlipped ? 0 : bounds.height - Self.crossHitSize,
                            width: Self.crossHitSize, height: Self.crossHitSize)
        return corner.contains(p)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let resizeCorner = Self.resizeRect(in: bounds, flipped: isFlipped)
        if resizeCorner.contains(point) {
            downPoint = nil
            resizeStart = (NSEvent.mouseLocation, bounds.size, cardScale)
            onResizeState(true)
            Self.resizeCursor.set()
            return
        }
        let pinCorner = NSRect(x: bounds.width - Self.crossHitSize,
                               y: isFlipped ? 0 : bounds.height - Self.crossHitSize,
                               width: Self.crossHitSize, height: Self.crossHitSize)
        if pinCorner.contains(point) {
            downPoint = nil
            onPin()
            return
        }
        if isInCross(event) {
            downPoint = nil
            onDiscard()
            return
        }
        if event.clickCount == 2 {
            downPoint = nil
            onDoubleClick()
            return
        }
        downPoint = event.locationInWindow
        startedDrag = false
        didLongPress = false
        onPressChange(true)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.downPoint != nil, !self.startedDrag else { return }
                self.didLongPress = true
                self.onPressChange(false)
                self.onLongPress()
            }
        }
    }

    private func endPress() {
        holdTimer?.invalidate()
        holdTimer = nil
        onPressChange(false)
    }

    override func mouseDragged(with event: NSEvent) {
        if let start = resizeStart {
            Self.resizeCursor.set()
            let mouse = NSEvent.mouseLocation
            let deltaX = mouse.x - start.point.x
            let deltaY = start.point.y - mouse.y
            let lengthSquared = start.size.width * start.size.width + start.size.height * start.size.height
            let ratio = 1 + (deltaX * start.size.width + deltaY * start.size.height) / max(1, lengthSquared)
            onResize(start.scale * ratio)
            return
        }
        guard let start = downPoint, !startedDrag, let url else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4, !didLongPress else { return }
        startedDrag = true
        endPress()

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(imageFrame(), contents: dragImage)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        // Released where nothing accepts it: it flies back to the line.
        session.animatesToStartingPositionsOnCancelOrFail = true
        GrabView.isDragging = true
        onDragStart()
    }

    override func mouseUp(with event: NSEvent) {
        if resizeStart != nil {
            resizeStart = nil
            onResizeState(false)
            window?.invalidateCursorRects(for: self)
            updatePointer(at: convert(event.locationInWindow, from: nil))
            return
        }
        endPress()
        if downPoint != nil && !startedDrag && !didLongPress && event.clickCount == 1 { onClick() }
        downPoint = nil
        didLongPress = false
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Sharing a hanging image sends a copy and leaves the source in place.
        [.copy, .delete]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        GrabView.isDragging = false
        startedDrag = false
        downPoint = nil
        log.notice("Drag ended with operation \(operation.rawValue, privacy: .public)")
        // Dropped on the Trash: macOS only tells us, we move the file.
        if operation.contains(.delete) {
            onDragEnd()
            onTrash()
            return
        }
        onDragEnd()
    }

    /// The drag preview keeps the photo's aspect ratio inside the card.
    private func imageFrame() -> NSRect {
        guard let size = dragImage?.size, size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
