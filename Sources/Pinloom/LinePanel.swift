import AppKit

/// A transparent strip along the top of the screen that floats over every
/// app and every Space without activating its app. Text editing can request
/// keyboard focus; clicks elsewhere pass through to the working app.
final class LinePanel: NSPanel {
    static let overlayBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary, .ignoresCycle
    ]
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        title = L("Pinloom line")
        level = .floating
        collectionBehavior = Self.overlayBehavior
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        contentView = content
    }

    // Only text controls request key status (becomesKeyOnlyIfNeeded). The
    // nonactivating style keeps the user's working application active.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if NoteEditingCommands.perform(event, on: firstResponder) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Use the actual native hit target instead of asynchronous SwiftUI
    /// geometry preferences, which may still be empty at first presentation.
    func interactiveView(atWindowPoint point: NSPoint) -> NSView? {
        guard let content = contentView else { return nil }
        let pointInParent = content.superview?.convert(point, from: nil) ?? point
        var hit = content.hitTest(pointInParent)
        while let view = hit {
            if view is GrabView || view is LineDismissView || view is ClipMoveView || view is LineImportView
                || view is StickyNoteBody || view is NoteResizeView { return view }
            hit = view.superview
        }
        return nil
    }

    /// The line hangs on the screen you are using, which is the one with the
    /// pointer: that is where you just opened the line.
    static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Reserve the header even when the full-screen menu bar is temporarily hidden.
    static func usableFrame(of screen: NSScreen) -> NSRect {
        var visible = screen.visibleFrame
        let top = screen.frame.maxY - max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        if visible.maxY > top { visible.size.height -= visible.maxY - top }
        return visible
    }

    func placeOnScreen(_ screen: NSScreen? = nil, height: CGFloat = Layout.panelHeight) {
        guard let screen = screen ?? LinePanel.screenUnderPointer() else { return }
        let visible = Self.usableFrame(of: screen)
        let height = min(height, visible.height)
        let target = NSRect(x: visible.minX, y: visible.maxY - height, width: visible.width, height: height)
        if frame != target { setFrame(target, display: true) }
    }
}
