import AppKit
import SwiftUI

struct ReferenceRecord: Codable, Identifiable {
    let id: UUID
    let sourcePath: String
    let filename: String
    var frame: String?
    var zoom: Double = 1
}

/// Reference images own snapshots, so moving or deleting an original can't interrupt a task.
@MainActor
final class ReferenceLibrary: ObservableObject {
    @Published private(set) var records: [ReferenceRecord] = []
    let folder: URL
    private let defaults: UserDefaults

    init(folder: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinloom/References", isDirectory: true)
        if let data = defaults.data(forKey: "referenceImages"),
           let saved = try? JSONDecoder().decode([ReferenceRecord].self, from: data) {
            records = saved.filter {
                // Only files created by this library may be opened or removed.
                $0.filename == "\($0.id.uuidString).\(($0.filename as NSString).pathExtension)"
                    && FileManager.default.fileExists(atPath: url(for: $0).path)
            }
        }
    }

    func url(for record: ReferenceRecord) -> URL { folder.appendingPathComponent(record.filename) }

    func pin(_ source: URL) throws -> ReferenceRecord {
        let path = source.imageIdentityPath
        if let existing = records.first(where: { $0.sourcePath == path }) { return existing }
        guard makeThumbnail(source) != nil else { throw CocoaError(.fileReadCorruptFile) }
        let id = UUID()
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let record = ReferenceRecord(id: id, sourcePath: path, filename: "\(id.uuidString).\(ext)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: url(for: record))
        records.append(record)
        save()
        return record
    }

    func remove(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: url(for: record))
        records.removeAll { $0.id == id }
        save()
    }

    func update(_ id: UUID, frame: NSRect, zoom: Double) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].frame = NSStringFromRect(frame)
        records[index].zoom = zoom
        save()
    }

    private func save() { defaults.set(try? JSONEncoder().encode(records), forKey: "referenceImages") }
}

/// Independent, nonactivating panels keep the working app in front, even in full screen.
@MainActor
final class ReferenceImages {
    let library: ReferenceLibrary
    private var windows: [UUID: ImageWindowController] = [:]
    private var preview: ImageWindowController?
    private(set) var hidden = false
    var onError: (Error) -> Void = { _ in }

    init(library: ReferenceLibrary? = nil) { self.library = library ?? ReferenceLibrary() }

    func restore() {
        for record in library.records { show(record) }
    }

    func pin(_ url: URL) {
        do {
            let record = try library.pin(url)
            hidden = false
            for controller in windows.values { controller.window?.orderFrontRegardless() }
            show(record)
        } catch { onError(error) }
    }

    private func show(_ record: ReferenceRecord) {
        if let existing = windows[record.id] { existing.window?.orderFrontRegardless(); return }
        let controller = ImageWindowController(url: library.url(for: record),
                                               frame: record.frame.map(NSRectFromString), zoom: record.zoom)
        controller.onClose = { [weak self] in
            self?.library.remove(record.id)
            self?.windows[record.id] = nil
        }
        controller.onChange = { [weak self, weak controller] in
            guard let controller, let frame = controller.window?.frame else { return }
            self?.library.update(record.id, frame: frame, zoom: controller.zoom)
        }
        windows[record.id] = controller
        controller.window?.orderFrontRegardless()
    }

    func showPreview(_ url: URL) {
        preview?.window?.close()
        let controller = ImageWindowController(url: url, frame: nil, zoom: 1, onPin: { [weak self] in
            self?.pin(url)
            self?.preview?.window?.close()
        })
        controller.onClose = { [weak self] in self?.preview = nil }
        preview = controller
        controller.window?.orderFrontRegardless()
    }

    func toggleHidden() {
        guard !windows.isEmpty else { return }
        hidden.toggle()
        for controller in windows.values {
            if hidden { controller.window?.orderOut(nil) } else { controller.window?.orderFrontRegardless() }
        }
    }

    func saveFrames() { for controller in windows.values { controller.onChange() } }

    func reposition() {
        for controller in windows.values { controller.keepOnScreen() }
        preview?.keepOnScreen()
    }
}

private final class ReferencePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ImageWindowController: NSWindowController, NSWindowDelegate {
    var onClose: () -> Void = {}
    var onChange: () -> Void = {}
    private(set) var zoom: Double

    init(url: URL, frame: NSRect?, zoom: Double, onPin: (() -> Void)? = nil) {
        self.zoom = zoom.isFinite ? max(0.25, min(128, zoom)) : 1
        let screen = LinePanel.screenUnderPointer()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let image = NSImage(contentsOf: url) ?? NSImage()
        let scale = min(1, min(screen.width * 0.55 / max(1, image.size.width),
                               screen.height * 0.65 / max(1, image.size.height)))
        let size = NSSize(width: max(280, image.size.width * scale), height: max(200, image.size.height * scale + 42))
        let panel = ReferencePanel(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.title = onPin == nil ? L("Reference image") : L("Image preview")
        panel.level = .floating
        panel.collectionBehavior = LinePanel.overlayBehavior
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 280, height: 180)
        panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 60))
        super.init(window: panel)
        if let frame, frame.width.isFinite, frame.height.isFinite,
           frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width >= 280, frame.height >= 180 {
            panel.setFrame(frame, display: false)
        }
        keepOnScreen()
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ReferenceImageView(image: image, zoom: self.zoom, onPin: onPin) { [weak self] zoom in
            self?.zoom = zoom
            self?.onChange()
        })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { onClose() }
    func windowDidMove(_ notification: Notification) { onChange() }
    func windowDidResize(_ notification: Notification) { onChange() }

    func keepOnScreen() {
        guard let window else { return }
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(window.frame) })
            ?? LinePanel.screenUnderPointer()
        guard let area = screen?.visibleFrame else { return }
        var frame = window.frame
        frame.size.width = min(frame.width, area.width)
        frame.size.height = min(frame.height, area.height)
        frame.origin.x = max(area.minX, min(frame.minX, area.maxX - frame.width))
        frame.origin.y = max(area.minY, min(frame.minY, area.maxY - frame.height))
        window.setFrame(frame, display: true)
    }
}

private struct ReferenceImageView: View {
    let image: NSImage
    @State var zoom: Double
    let onPin: (() -> Void)?
    let onZoom: (Double) -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let fit = min(geometry.size.width / max(1, image.size.width),
                              geometry.size.height / max(1, image.size.height))
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: max(1, image.size.width * fit * zoom),
                               height: max(1, image.size.height * fit * zoom))
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button("100%") { setZoom(1 / max(0.001, fit)) }
                        .buttonStyle(.bordered).padding(8)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Button(action: { setZoom(zoom / 1.25) }) { Image(systemName: "minus.magnifyingglass") }
                    .help(L("Zoom out"))
                Button(L("Fit")) { setZoom(1) }
                Button(action: { setZoom(zoom * 1.25) }) { Image(systemName: "plus.magnifyingglass") }
                    .help(L("Zoom in"))
                Spacer()
                Button(L("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
                if let onPin {
                    Button(action: onPin) { Label(L("Pin reference image"), systemImage: "pin") }
                }
            }.buttonStyle(.borderless).padding(.horizontal, 12).frame(height: 38)
        }
        .background(.regularMaterial)
    }

    private func setZoom(_ value: Double) {
        zoom = max(0.25, min(128, value))
        onZoom(zoom)
    }
}
