import SwiftUI

// Hallmark · component: paper note · native system type · warm neutral palette
// Pre-emit critique: P4 H4 E4 S4 R5 V4
private enum NoteStyle {
    static let paper = NSColor(srgbRed: 0.99, green: 0.975, blue: 0.92, alpha: 1)
    static let ink = NSColor(srgbRed: 0.22, green: 0.23, blue: 0.21, alpha: 1)
    static let muted = NSColor(srgbRed: 0.43, green: 0.44, blue: 0.39, alpha: 1)
    static let rule = NSColor(srgbRed: 0.84, green: 0.83, blue: 0.76, alpha: 1)
    static let accent = NSColor(srgbRed: 0.22, green: 0.40, blue: 0.35, alpha: 1)
    static let bodyFont = NSFont.systemFont(ofSize: 14)
    static let inset: CGFloat = 18
    static let radius: CGFloat = 8
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
                .background(Color(nsColor: NoteStyle.paper), in: RoundedRectangle(cornerRadius: NoteStyle.radius))
                .clipShape(RoundedRectangle(cornerRadius: NoteStyle.radius))
                .overlay(RoundedRectangle(cornerRadius: NoteStyle.radius)
                    .strokeBorder(Color(nsColor: NoteStyle.rule).opacity(0.6), lineWidth: 0.5).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Color(nsColor: NoteStyle.muted))
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
                withAttributes: [.font: font ?? NoteStyle.bodyFont, .foregroundColor: NoteStyle.muted])
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
    private let document = FlippedNoteView()
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
    private var pendingFocus: UUID?

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .aqua)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = NoteStyle.muted
        removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Remove note"))
        removeButton.bezelStyle = .inline
        removeButton.showsBorderOnlyWhileMouseInside = true
        removeButton.contentTintColor = NoteStyle.muted
        removeButton.target = self; removeButton.action = #selector(removeNote)
        removeButton.toolTip = L("Remove note")
        addButton.bezelStyle = .inline; addButton.controlSize = .regular
        addButton.showsBorderOnlyWhileMouseInside = true
        addButton.font = .systemFont(ofSize: 12, weight: .medium)
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.contentTintColor = NoteStyle.accent
        addButton.target = self; addButton.action = #selector(addTask)
        memo.isRichText = false; memo.isEditable = true; memo.isSelectable = true
        memo.drawsBackground = false; memo.allowsUndo = true
        memo.font = NoteStyle.bodyFont; memo.textColor = NoteStyle.ink
        memo.insertionPointColor = NoteStyle.accent
        memo.textContainerInset = NSSize(width: 0, height: 4)
        memo.textContainer?.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        memo.defaultParagraphStyle = paragraph
        memo.isVerticallyResizable = true; memo.isHorizontallyResizable = false
        memo.autoresizingMask = [.width]; memo.textContainer?.widthTracksTextView = true
        memo.delegate = self
        memo.setAccessibilityLabel(L("Note text"))
        memo.onEscape = { [weak self] in self?.onFinish() }
        memoScroll.documentView = document; memoScroll.hasVerticalScroller = true
        memoScroll.autohidesScrollers = true; memoScroll.drawsBackground = false
        document.addSubview(memo)
        document.addSubview(taskDocument)
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: L("Copy note"))
        copyButton.bezelStyle = .inline
        copyButton.showsBorderOnlyWhileMouseInside = true
        copyButton.contentTintColor = NoteStyle.muted
        copyButton.target = self; copyButton.action = #selector(copyNote)
        copyButton.toolTip = L("Copy note")
        [title, copyButton, removeButton, memoScroll, addButton].forEach(addSubview)
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
        onFinish = { [weak self] in
            self?.pendingTask = nil; self?.pendingFocus = nil
            line.editingNoteID = nil; line.onFinishNoteEditing()
        }
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
                          onReturn: { [weak self] text, selection in
                              guard let self else { return nil }
                              switch line.continueTask(task.id, in: note.id, text: text, selection: selection) {
                              case .inserted(let id, let leadingText):
                                  self.onBegin()
                                  self.pendingTask = id
                                  if let current = line.notes.first(where: { $0.id == note.id }) {
                                      self.configure(note: current, line: line)
                                  }
                                  return leadingText
                              case .finished:
                                  self.window?.makeFirstResponder(nil)
                                  self.onFinish()
                                  return nil
                              case .ignored: return nil
                              }
                          },
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
            pendingFocus = pendingTask
            DispatchQueue.main.async { [weak self, weak row, weak line] in
                guard let self, let row, let line, self.pendingFocus == pendingTask,
                      self.rows[pendingTask] === row,
                      line.editingNoteID == note.id,
                      let window = self.window, window.isVisible else { return }
                self.pendingFocus = nil
                self.layoutSubtreeIfNeeded()
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(row.field)
                (row.field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: 0))
                row.scrollToVisible(row.bounds)
            }
        }
    }
    override func layout() {
        super.layout()
        let width = bounds.width, inset = NoteStyle.inset
        title.frame = NSRect(x: inset, y: 14, width: max(0, width - 100), height: 18)
        copyButton.frame = NSRect(x: width - 76, y: 9, width: 28, height: 28)
        removeButton.frame = NSRect(x: width - 44, y: 9, width: 28, height: 28)
        memoScroll.frame = NSRect(x: inset, y: 48, width: max(0, width - inset * 2), height: max(0, bounds.height - 96))
        let contentWidth = memoScroll.contentSize.width
        memo.setFrameSize(NSSize(width: contentWidth, height: max(40, memo.frame.height)))
        memo.layoutManager?.ensureLayout(for: memo.textContainer!)
        let textHeight = ceil(memo.layoutManager?.usedRect(for: memo.textContainer!).height ?? 0) + 12
        let memoHeight = order.isEmpty ? max(memoScroll.contentSize.height, textHeight) : max(32, textHeight)
        memo.frame = NSRect(x: 0, y: 0, width: contentWidth, height: memoHeight)
        let tasksTop = memoHeight + 12
        taskDocument.isHidden = order.isEmpty
        taskDocument.frame = NSRect(x: 0, y: tasksTop, width: contentWidth, height: CGFloat(order.count) * 34)
        document.frame = NSRect(x: 0, y: 0, width: contentWidth,
                                height: max(memoScroll.contentSize.height, order.isEmpty ? memoHeight : taskDocument.frame.maxY))
        for (index, id) in order.enumerated() {
            rows[id]?.frame = NSRect(x: 0, y: CGFloat(index) * 34, width: contentWidth, height: 32)
        }
        addButton.frame = NSRect(x: inset - 4, y: bounds.height - 39, width: 112, height: 28)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NoteStyle.rule.withAlphaComponent(0.6).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: NoteStyle.inset, y: bounds.height - 46))
        separator.line(to: NSPoint(x: bounds.width - NoteStyle.inset, y: bounds.height - 46))
        separator.lineWidth = 0.5
        separator.stroke()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func textDidBeginEditing(_ notification: Notification) { onBegin() }
    func textDidChange(_ notification: Notification) { onText(memo.string); needsLayout = true }
    @objc private func removeNote() { onRemove() }
    @objc private func copyNote() { onCopy() }
    @objc private func addTask() { onBegin(); pendingTask = onAddTask() }
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
    private var onReturn: (String, NSRange) -> String? = { _, _ in nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = NoteStyle.bodyFont; field.placeholderString = L("To-do")
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.delegate = self
        checkbox.contentTintColor = NoteStyle.accent
        checkbox.target = self; checkbox.action = #selector(check)
        removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Remove to-do"))
        removeButton.contentTintColor = NoteStyle.muted
        removeButton.bezelStyle = .inline; removeButton.target = self; removeButton.action = #selector(removeTask)
        removeButton.showsBorderOnlyWhileMouseInside = true
        removeButton.toolTip = L("Remove to-do")
        [checkbox, field, removeButton].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(task: NoteTask, onText: @escaping (String) -> Void, onCheck: @escaping (Bool) -> Void,
                   onRemove: @escaping () -> Void, onReturn: @escaping (String, NSRange) -> String?,
                   onBegin: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onText = onText; self.onCheck = onCheck; self.onRemove = onRemove
        self.onReturn = onReturn
        self.onBegin = onBegin; self.onFinish = onFinish
        if field.stringValue != task.text { field.stringValue = task.text }
        checkbox.state = task.completed ? .on : .off
        checkbox.setAccessibilityLabel(task.text.isEmpty ? L("To-do") : task.text)
        field.textColor = task.completed ? NoteStyle.muted : NoteStyle.ink
        if field.currentEditor() == nil {
            field.attributedStringValue = NSAttributedString(string: task.text, attributes: [
                .font: NoteStyle.bodyFont, .foregroundColor: task.completed ? NoteStyle.muted : NoteStyle.ink,
                .strikethroughStyle: task.completed ? NSUnderlineStyle.single.rawValue : 0
            ])
        }
    }
    override func layout() {
        super.layout()
        checkbox.frame = NSRect(x: 0, y: 5, width: 22, height: 22)
        field.frame = NSRect(x: 28, y: 6, width: max(30, bounds.width - 56), height: 22)
        removeButton.frame = NSRect(x: bounds.width - 24, y: 4, width: 24, height: 24)
    }
    func controlTextDidBeginEditing(_ notification: Notification) { onBegin() }
    func controlTextDidChange(_ notification: Notification) { onText(field.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // Let the input method use Return to confirm marked text first.
        guard !textView.hasMarkedText() else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if let prefix = onReturn(textView.string, textView.selectedRange()) {
                textView.string = prefix
                field.stringValue = prefix
                textView.setSelectedRange(NSRange(location: (prefix as NSString).length, length: 0))
            }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) { onFinish(); return true }
        return false
    }
    @objc private func check() { onCheck(checkbox.state == .on) }
    @objc private func removeTask() { onRemove() }
}
