import AppKit
import SwiftUI

extension URL {
    var imageIdentityPath: String { standardizedFileURL.resolvingSymlinksInPath().path }
}

enum ImageImport {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinloom/Imports", isDirectory: true)
    }
    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    static func supports(_ pasteboard: NSPasteboard) -> Bool {
        !urls(from: pasteboard).isEmpty || MediaImport.webpageURL(from: pasteboard) != nil
            || pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }
    static func imageFile(from pasteboard: NSPasteboard, in destination: URL = folder) throws -> URL? {
        guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let url = destination.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try png.write(to: url, options: .atomic)
        return url
    }
}

final class StatusDropView: NSView {
    var onDrop: (NSPasteboard) -> Bool = { _ in false }
    var onClick: () -> Void = {}
    var onRightClick: () -> Void = {}
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
        toolTip = L("Click to show or hide the line. Right-click for the menu.")
        setAccessibilityHelp(toolTip)
        setAccessibilityLabel(L("Show or hide line"))
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func rightMouseDown(with event: NSEvent) { onRightClick() }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImageImport.supports(sender.draggingPasteboard) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { onDrop(sender.draggingPasteboard) }
}

final class DropHostingView: NSHostingView<LineView> {
    var onDrop: (NSPasteboard) -> Bool = { _ in false }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImageImport.supports(sender.draggingPasteboard) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { onDrop(sender.draggingPasteboard) }
}
