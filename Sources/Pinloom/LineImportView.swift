import SwiftUI

enum LineImportAction {
    case clipboard, files, note, webpage
    var title: String {
        switch self {
        case .clipboard: return L("Paste")
        case .files: return L("Add files…")
        case .note: return L("New note")
        case .webpage: return L("Add webpage…")
        }
    }
    var symbol: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .files: return "photo.badge.plus"
        case .note: return "note.text.badge.plus"
        case .webpage: return "globe"
        }
    }
}

struct LineImportArea: NSViewRepresentable {
    let line: Line
    let action: LineImportAction
    func makeNSView(context: Context) -> LineImportView { LineImportView() }
    func updateNSView(_ view: LineImportView, context: Context) {
        view.configure(line: line, action: action)
    }
}

/// A visible import target catches drops even when the rest of the empty
/// line passes clicks through. Both buttons also accept dragged images.
final class LineImportView: NSView {
    private var onPress: () -> Void = {}
    private var onDrop: (NSPasteboard) -> Bool = { _ in false }
    private var onReceivingDrop: (Bool) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(line: Line, action: LineImportAction) {
        onPress = {
            switch action {
            case .clipboard: line.onPasteImage()
            case .files: line.onChooseImages()
            case .note: line.onCreateNote()
            case .webpage: line.onAddWebpage()
            }
        }
        onDrop = { line.onImportImages($0) }
        onReceivingDrop = { line.receivingDrop = $0 }
        setAccessibilityLabel(action.title)
        toolTip = action.title
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onPress() }
    override func accessibilityPerformPress() -> Bool { onPress(); return true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = ImageImport.supports(sender.draggingPasteboard)
        onReceivingDrop(accepts)
        return accepts ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onReceivingDrop(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onReceivingDrop(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onReceivingDrop(false) }
        return onDrop(sender.draggingPasteboard)
    }
}
