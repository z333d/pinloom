import SwiftUI

private enum NoteStyle {
    static let paper = Color(red: 0.98, green: 0.94, blue: 0.72)
}

struct StickyNoteCard: View {
    let note: StickyNote
    @ObservedObject var line: Line
    let anchor: CGPoint
    @StateObject private var motion = HangingMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = line.noteSize(note)
        VStack(spacing: -12) {
            Clothespin().frame(width: 32, height: 26)
                .overlay(NoteClipArea(note: note, line: line, anchor: anchor, motion: motion, reduceMotion: reduceMotion))
                .zIndex(1)
            StickyNoteContent(note: note, line: line)
                .frame(width: size.width, height: size.height)
                .background(NoteStyle.paper, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.black.opacity(0.55))
                        .frame(width: 26, height: 26).allowsHitTesting(false)
                        .overlay(NoteResizeArea(note: note, line: line).frame(width: 26, height: 26))
                }
        }
        .frame(width: size.width + 20, height: size.height + 14)
        .rotationEffect(.degrees(line.editingNoteID == note.id ? 0 : motion.degrees), anchor: .top)
        .onDisappear { motion.stop() }
    }
}

private struct NoteClipArea: NSViewRepresentable {
    let note: StickyNote
    let line: Line
    let anchor: CGPoint
    let motion: HangingMotion
    let reduceMotion: Bool
    func makeNSView(context: Context) -> ClipMoveView { ClipMoveView() }
    func updateNSView(_ view: ClipMoveView, context: Context) {
        view.anchor = anchor
        view.onMove = { point in
            line.moveNote(note.id, to: point)
            if !reduceMotion, let current = line.notes.first(where: { $0.id == note.id }), let x = current.x, let y = current.y {
                motion.move(to: CGPoint(x: x, y: y))
            }
        }
        view.onMoveState = { moving in
            line.movingItemID = moving ? note.id : nil
            if moving {
                line.frontmostItemID = note.id
                if !reduceMotion { motion.begin(at: anchor, length: line.noteSize(note).height / 2) }
            } else { motion.release() }
        }
        view.resetTitle = L("Reset note position")
        view.onReset = { line.resetNotePosition(note.id) }
    }
}

private struct NoteResizeArea: NSViewRepresentable {
    let note: StickyNote
    let line: Line
    func makeNSView(context: Context) -> NoteResizeView { NoteResizeView() }
    func updateNSView(_ view: NoteResizeView, context: Context) {
        view.size = line.noteSize(note)
        view.onResize = { line.resizeNote(note.id, to: $0) }
        view.onState = { line.resizingID = $0 ? note.id : nil }
    }
}

final class NoteResizeView: NSView {
    var size = CGSize.zero
    var onResize: (CGSize) -> Void = { _ in }
    var onState: (Bool) -> Void = { _ in }
    private var start: (point: NSPoint, size: CGSize)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: GrabView.resizeCursor) }
    override func mouseDown(with event: NSEvent) {
        start = (NSEvent.mouseLocation, size); onState(true); GrabView.resizeCursor.set()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let mouse = NSEvent.mouseLocation
        GrabView.resizeCursor.set()
        onResize(CGSize(width: start.size.width + mouse.x - start.point.x,
                        height: start.size.height + start.point.y - mouse.y))
    }
    override func mouseUp(with event: NSEvent) { start = nil; onState(false) }
}

private struct StickyNoteContent: NSViewRepresentable {
    let note: StickyNote
    let line: Line
    func makeNSView(context: Context) -> StickyNoteBody { StickyNoteBody() }
    func updateNSView(_ view: StickyNoteBody, context: Context) { view.configure(note: note, line: line) }
}

final class NoteTextView: NSTextView {
    var onEscape: () -> Void = {}
    var copyPasteboard: NSPasteboard = .general
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func copy(_ sender: Any?) {
        let range = selectedRange()
        let contents = string as NSString
        guard range.length > 0, range.location != NSNotFound,
              NSMaxRange(range) <= contents.length else { return }
        copyPasteboard.clearContents()
        copyPasteboard.setString(contents.substring(with: range), forType: .string)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        NoteEditingCommands.perform(event, on: self) || super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if NoteEditingCommands.perform(event, on: self) { return }
        if event.keyCode == 53 { onEscape() } else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (L("Write a note…") as NSString).draw(at: CGPoint(x: textContainerInset.width, y: textContainerInset.height),
                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])
        }
    }
}

final class StickyNoteBody: NSView, NSTextViewDelegate {
    override var isFlipped: Bool { true }
    private let title = NSTextField(labelWithString: L("Note"))
    private let removeButton = NSButton()
    private let copyButton = NSButton()
    private let addButton = NSButton(title: L("Add to-do"), target: nil, action: nil)
    private let memo = NoteTextView()
    private let memoScroll = NSScrollView()
    private let taskScroll = NSScrollView()
    private let taskDocument = FlippedNoteView()
    private var rows: [UUID: NoteTaskRow] = [:]
    private var order: [UUID] = []
    private var onText: (String) -> Void = { _ in }
    private var onRemove: () -> Void = {}
    private var onCopy: () -> Void = {}
    private var clipboard: NSPasteboard = .general
    private var onAddTask: () -> UUID? = { nil }
    private var onBegin: () -> Void = {}
    private var onFinish: () -> Void = {}
    private var pendingTask: UUID?

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .aqua)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Remove note"))
        removeButton.isBordered = false
        removeButton.target = self; removeButton.action = #selector(removeNote)
        removeButton.toolTip = L("Remove note")
        addButton.bezelStyle = .rounded; addButton.controlSize = .small
        addButton.target = self; addButton.action = #selector(addTask)
        memo.isRichText = false; memo.isEditable = true; memo.isSelectable = true
        memo.drawsBackground = false; memo.allowsUndo = true
        memo.font = .systemFont(ofSize: 13); memo.textColor = .labelColor
        memo.textContainerInset = NSSize(width: 3, height: 4)
        memo.isVerticallyResizable = true; memo.isHorizontallyResizable = false
        memo.autoresizingMask = [.width]; memo.textContainer?.widthTracksTextView = true
        memo.delegate = self
        memo.setAccessibilityLabel(L("Note text"))
        memo.onEscape = { [weak self] in self?.onFinish() }
        memoScroll.documentView = memo; memoScroll.hasVerticalScroller = true
        memoScroll.autohidesScrollers = true; memoScroll.drawsBackground = false
        taskScroll.documentView = taskDocument; taskScroll.hasVerticalScroller = true
        taskScroll.autohidesScrollers = true; taskScroll.drawsBackground = false
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: L("Copy note"))
        copyButton.isBordered = false
        copyButton.target = self; copyButton.action = #selector(copyNote)
        copyButton.toolTip = L("Copy note")
        [title, copyButton, removeButton, memoScroll, taskScroll, addButton].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    convenience init(clipboard: NSPasteboard) {
        self.init(frame: .zero)
        self.clipboard = clipboard
        memo.copyPasteboard = clipboard
    }

    func configure(note: StickyNote, line: Line) {
        onText = { line.setNoteText(note.id, text: $0) }
        onRemove = { line.removeNote(note.id) }
        onCopy = { [weak self] in
            guard let self, let current = line.notes.first(where: { $0.id == note.id }) else { return }
            self.clipboard.clearContents()
            self.clipboard.setString(current.plainText, forType: .string)
        }
        onAddTask = { line.addTask(to: note.id) }
        onBegin = { line.editingNoteID = note.id }
        onFinish = { line.editingNoteID = nil; line.onFinishNoteEditing() }
        if memo.string != note.text { memo.string = note.text }
        memo.needsDisplay = true
        let taskIDs = note.tasks.map(\.id)
        for id in order where !taskIDs.contains(id) { rows.removeValue(forKey: id)?.removeFromSuperview() }
        order = taskIDs
        for task in note.tasks {
            let row = rows[task.id] ?? NoteTaskRow()
            if rows[task.id] == nil { rows[task.id] = row; taskDocument.addSubview(row) }
            row.configure(task: task,
                          onText: { line.setTask(task.id, in: note.id, text: $0) },
                          onCheck: { line.setTask(task.id, in: note.id, completed: $0) },
                          onRemove: { line.removeTask(task.id, from: note.id) },
                          onBegin: onBegin, onFinish: onFinish)
        }
        needsLayout = true
        if line.noteFocusRequest == note.id {
            DispatchQueue.main.async { [weak self, weak line] in
                guard let self, let line, line.noteFocusRequest == note.id else { return }
                self.layoutSubtreeIfNeeded()
                self.scrollToVisible(self.bounds)
                guard let window = self.window, window.isVisible else { return }
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(self.memo)
                line.editingNoteID = note.id
                line.noteFocusRequest = nil
            }
        }
        if let pendingTask, let row = rows[pendingTask] {
            self.pendingTask = nil
            DispatchQueue.main.async { [weak self, weak row] in
                guard let self, let row else { return }
                self.layoutSubtreeIfNeeded()
                row.scrollToVisible(row.bounds)
                self.window?.makeKeyAndOrderFront(nil)
                self.window?.makeFirstResponder(row.field)
                self.onBegin()
            }
        }
    }
    override func layout() {
        super.layout()
        let width = bounds.width
        title.frame = NSRect(x: 12, y: 9, width: width - 80, height: 18)
        copyButton.frame = NSRect(x: width - 64, y: 6, width: 24, height: 24)
        removeButton.frame = NSRect(x: width - 36, y: 6, width: 24, height: 24)
        let memoHeight = order.isEmpty ? max(40, bounds.height - 72) : max(40, min(120, bounds.height * 0.4))
        memoScroll.frame = NSRect(x: 12, y: 34, width: width - 24, height: memoHeight)
        memo.setFrameSize(NSSize(width: memoScroll.contentSize.width, height: max(memoHeight, memo.frame.height)))
        let tasksTop = 40 + memoHeight
        taskScroll.frame = NSRect(x: 12, y: tasksTop, width: width - 24, height: max(20, bounds.height - tasksTop - 34))
        taskScroll.isHidden = order.isEmpty
        taskDocument.frame = NSRect(x: 0, y: 0, width: taskScroll.contentSize.width, height: CGFloat(order.count) * 28)
        for (index, id) in order.enumerated() {
            rows[id]?.frame = NSRect(x: 0, y: CGFloat(index) * 28, width: taskDocument.bounds.width, height: 26)
        }
        addButton.frame = NSRect(x: 12, y: bounds.height - 30, width: 108, height: 24)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func textDidBeginEditing(_ notification: Notification) { onBegin() }
    func textDidChange(_ notification: Notification) { onText(memo.string) }
    @objc private func removeNote() { onRemove() }
    @objc private func copyNote() { onCopy() }
    @objc private func addTask() { pendingTask = onAddTask() }
}

private final class FlippedNoteView: NSView { override var isFlipped: Bool { true } }

private final class NoteTaskRow: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    let field = NSTextField()
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let removeButton = NSButton()
    private var onText: (String) -> Void = { _ in }
    private var onCheck: (Bool) -> Void = { _ in }
    private var onRemove: () -> Void = {}
    private var onBegin: () -> Void = {}
    private var onFinish: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: 13); field.placeholderString = L("To-do")
        field.delegate = self
        checkbox.target = self; checkbox.action = #selector(check)
        removeButton.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: L("Remove to-do"))
        removeButton.isBordered = false; removeButton.target = self; removeButton.action = #selector(removeTask)
        [checkbox, field, removeButton].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(task: NoteTask, onText: @escaping (String) -> Void, onCheck: @escaping (Bool) -> Void,
                   onRemove: @escaping () -> Void, onBegin: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onText = onText; self.onCheck = onCheck; self.onRemove = onRemove
        self.onBegin = onBegin; self.onFinish = onFinish
        if field.stringValue != task.text { field.stringValue = task.text }
        checkbox.state = task.completed ? .on : .off
        checkbox.setAccessibilityLabel(task.text.isEmpty ? L("To-do") : task.text)
        field.textColor = task.completed ? .secondaryLabelColor : .labelColor
    }
    override func layout() {
        super.layout()
        checkbox.frame = NSRect(x: 0, y: 2, width: 22, height: 22)
        field.frame = NSRect(x: 25, y: 3, width: max(30, bounds.width - 49), height: 22)
        removeButton.frame = NSRect(x: bounds.width - 22, y: 2, width: 22, height: 22)
    }
    func controlTextDidBeginEditing(_ notification: Notification) { onBegin() }
    func controlTextDidChange(_ notification: Notification) { onText(field.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { onFinish(); return true }
        return false
    }
    @objc private func check() { onCheck(checkbox.state == .on) }
    @objc private func removeTask() { onRemove() }
}
