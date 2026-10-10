import AppKit
import Combine
import os

let log = Logger(subsystem: "io.github.z333d.pinloom", category: "line")

/// One image hanging on the line.
struct Pegged: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var thumb: NSImage
    /// Every photo hangs a little crooked, like on a real line.
    let tilt = Double.random(in: -2.5...2.5)
    var falling = false
    var scale: CGFloat = CardSizing.defaultImageScale
    var hangingPosition: CGPoint?

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.thumb === b.thumb
            && a.scale == b.scale && a.hangingPosition == b.hangingPosition
    }
}

/// The line itself: what hangs on it and what you can do with each item.
/// The files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    @Published private(set) var items: [Pegged] = []
    @Published private(set) var gust = 0
    @Published var copiedID: UUID?
    @Published var draggingID: UUID?
    @Published var pressedID: UUID?
    @Published var resizingID: UUID?
    /// Whether the line has slid down into view.
    @Published var revealed = false
    @Published var pinnedPaths = Set<String>()
    var onPin: (URL) -> Void = { _ in }
    var onPreview: (URL) -> Void = { _ in }
    var onLayoutChange: () -> Void = {}
    @Published var movingItemID: UUID?
    @Published var frontmostItemID: UUID?
    var onHideLine: () -> Void = {}
    var onPasteImage: () -> Void = {}
    var onChooseImages: () -> Void = {}
    var onImportImages: (NSPasteboard) -> Bool = { _ in false }
    @Published var receivingDrop = false
    @Published private(set) var notes: [StickyNote] = []
    @Published private(set) var lastRemovedNote: StickyNote?
    @Published var editingNoteID: UUID?
    @Published var noteFocusRequest: UUID?
    var onCreateNote: () -> Void = {}
    var onFinishNoteEditing: () -> Void = {}

    /// Only explicit UI actions change visibility; image and note updates
    /// keep the current state. Hiding ends editing without deleting content.
    func setShown(_ shown: Bool) {
        if !shown {
            editingNoteID = nil
            noteFocusRequest = nil
        }
        guard revealed != shown else { return }
        revealed = shown
    }

    /// Card frames in window coordinates, reported by the views. The panel
    /// uses them to only catch clicks over photos and let the rest through.
    var hitRects: [UUID: CGRect] = [:]
    var clipRects: [UUID: CGRect] = [:]
    @Published var availableHeight: CGFloat = 900
    @Published var viewportWidth: CGFloat = 1440

    var availableSize: CGSize { CGSize(width: viewportWidth, height: availableHeight) }
    var displayItems: [Pegged] {
        items.map { item in
            var rendered = item
            rendered.scale = CardSizing.imageScale(item.scale, image: item.thumb.size, available: availableSize)
            return rendered
        }
    }

    var soundOn: Bool {
        get { !defaults.bool(forKey: "soundOff") }
        set { defaults.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }
    var totalCount: Int { liveCount + notes.count }
    func noteSize(_ note: StickyNote) -> CGSize {
        NoteLayout.size(note, available: CGSize(width: viewportWidth, height: availableHeight))
    }
    var notesWidth: CGFloat {
        notes.reduce(0) { $0 + noteSize($1).width + 20 } + CGFloat(notes.count) * 24
            - (items.isEmpty && !notes.isEmpty ? 24 : 0)
    }
    var panelHeight: CGFloat {
        let width = max(viewportWidth, contentWidth + 40)
        let rendered = displayItems
        let bottom = rendered.enumerated().map { index, item in
            HangingLayout.position(for: item, index: index, items: rendered, width: width, height: availableHeight, trailingWidth: notesWidth).y
                + PeggedView.cardSize(for: item.thumb.size, scale: item.scale).height + 40
        }.max() ?? 0
        let noteBottom = notes.enumerated().map { index, note in
            notePosition(note, index: index, width: width).y + noteSize(note).height + 40
        }.max() ?? 0
        return min(availableHeight, max(Layout.panelHeight, max(bottom, noteBottom)))
    }
    var contentWidth: CGFloat { Layout.rowWidth(items: displayItems) + notesWidth }

    func notePosition(_ note: StickyNote, index: Int, width: CGFloat) -> CGPoint {
        let start = (width - contentWidth) / 2
        let before = Layout.rowWidth(items: displayItems) + (items.isEmpty ? 0 : 24)
            + notes.prefix(index).reduce(0) { $0 + noteSize($1).width + 44 }
        let x = start + before + (noteSize(note).width + 20) / 2
        return NoteLayout.position(note, defaultX: x, size: noteSize(note), width: width, height: availableHeight)
    }

    private let storeKey = "pegged"
    private let defaults: UserDefaults
    private var modificationDates: [String: Date] = [:]
    private var savedScales: [String: Double]
    private var savedPositions: [String: [Double]]
    private var thumbnailLimits: [UUID: Int] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        savedScales = defaults.dictionary(forKey: "peggedScales") as? [String: Double] ?? [:]
        savedPositions = defaults.dictionary(forKey: "peggedPositions") as? [String: [Double]] ?? [:]
        if let data = defaults.data(forKey: "stickyNotes"), let restored = try? JSONDecoder().decode([StickyNote].self, from: data) {
            var seen = Set<UUID>()
            notes = restored.filter { seen.insert($0.id).inserted }.map { note in
                var note = note
                note.width = note.width.isFinite ? max(200, note.width) : Double(CardSizing.defaultNoteSize.width)
                note.height = note.height.isFinite ? max(160, note.height) : Double(CardSizing.defaultNoteSize.height)
                return note
            }
        }
        if let data = defaults.data(forKey: "lastRemovedNote") {
            lastRemovedNote = try? JSONDecoder().decode(StickyNote.self, from: data)
        }
        restore()
        scheduleGust()
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false) -> UUID? {
        guard !items.contains(where: { $0.url.imageIdentityPath == url.imageIdentityPath && !$0.falling }),
              let thumb = makeThumbnail(url) else { return nil }
        var item = Pegged(url: url, thumb: thumb)
        if let scale = savedScales[url.imageIdentityPath], scale.isFinite {
            item.scale = max(CardSizing.minimumImageScale, scale)
        } else {
            item.scale = CardSizing.imageScale(CardSizing.defaultImageScale, image: thumb.size, available: availableSize)
        }
        if let position = savedPositions[url.imageIdentityPath], position.count == 2,
           position.allSatisfy(\.isFinite) {
            item.hangingPosition = CGPoint(x: position[0], y: position[1])
        }
        let pixels = CardSizing.thumbnailPixels(scale: item.scale)
        if pixels > 480, let thumb = makeThumbnail(url, maxPixels: pixels) {
            item.thumb = thumb
        }
        thumbnailLimits[item.id] = pixels
        items.append(item)
        modificationDates[url.path] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        save()
        if !quietly { play("Tink", volume: 0.35) }
        return item.id
    }

    /// Called just before a photo starts falling, so the fall can be drawn
    /// over the whole screen.
    var onFall: ((Pegged) -> Void)?

    func drop(_ id: UUID, quietly: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        onFall?(items[i])
        items[i].falling = true
        thumbnailLimits[id] = nil
        hitRects[id] = nil
        save()
        if !quietly { play("Pop", volume: 0.25) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    func clear() {
        let live = items.filter { !$0.falling }
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.drop(item.id, quietly: n > 0)
            }
        }
    }

    /// Photos whose file was deleted or moved away fall off by themselves.
    func prune() {
        for item in items where !item.falling {
            if !FileManager.default.fileExists(atPath: item.url.path) {
                drop(item.id, quietly: true)
            } else {
                let date = (try? item.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if date != modificationDates[item.url.path] { reloadThumbnail(for: item.url) }
            }
        }
    }

    // MARK: Actions on one photo

    func copy(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let entry = NSPasteboardItem()
        if let png = pngData(item.url) { entry.setData(png, forType: .png) }
        entry.setString(item.url.absoluteString, forType: .fileURL)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([entry])

        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }

    func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.open(item.url)
    }

    func preview(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        onPreview(item.url)
    }

    func pin(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        onPin(item.url)
    }

    func isPinned(_ item: Pegged) -> Bool { pinnedPaths.contains(item.url.imageIdentityPath) }

    /// Resizing changes only this presentation, never the source image or other cards.
    func resize(_ id: UUID, scale: CGFloat) {
        guard scale.isFinite, let index = items.firstIndex(where: { $0.id == id && !$0.falling }) else { return }
        items[index].scale = CardSizing.imageScale(scale, image: items[index].thumb.size, available: availableSize)
        let pixels = CardSizing.thumbnailPixels(scale: items[index].scale)
        if pixels > (thumbnailLimits[id] ?? 480), let thumb = makeThumbnail(items[index].url, maxPixels: pixels) {
            items[index].thumb = thumb
            thumbnailLimits[id] = pixels
        }
        save()
        onLayoutChange()
    }

    /// Each clip has its own anchor; moving it never rearranges neighbouring cards.
    func move(_ id: UUID, to position: CGPoint) {
        guard position.x.isFinite, position.y.isFinite,
              let index = items.firstIndex(where: { $0.id == id && !$0.falling }) else { return }
        items[index].hangingPosition = position
        let width = max(viewportWidth, contentWidth + 40)
        let rendered = displayItems
        items[index].hangingPosition = HangingLayout.position(for: rendered[index], index: index,
                                                             items: rendered, width: width, height: availableHeight, trailingWidth: notesWidth)
        save()
        onLayoutChange()
    }

    func resetPosition(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id && !$0.falling }) else { return }
        items[index].hangingPosition = nil
        savedPositions[items[index].url.imageIdentityPath] = nil
        save()
        onLayoutChange()
    }

    func resetPositions() {
        for index in items.indices { items[index].hangingPosition = nil }
        for index in notes.indices { notes[index].x = nil; notes[index].y = nil }
        saveNotes()
        savedPositions.removeAll()
        save()
        onLayoutChange()
    }

    // MARK: Notes

    @discardableResult
    func addNote() -> UUID {
        let note = StickyNote()
        notes.append(note)
        saveNotes()
        onLayoutChange()
        return note.id
    }
    func setNoteText(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        saveNotes()
    }
    @discardableResult
    func addTask(to id: UUID) -> UUID? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return nil }
        let task = NoteTask()
        notes[index].tasks.append(task)
        saveNotes()
        return task.id
    }
    func setTask(_ taskID: UUID, in noteID: UUID, text: String? = nil, completed: Bool? = nil) {
        guard let n = notes.firstIndex(where: { $0.id == noteID }),
              let t = notes[n].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if let text { notes[n].tasks[t].text = text }
        if let completed { notes[n].tasks[t].completed = completed }
        saveNotes()
    }
    func continueTask(_ taskID: UUID, in noteID: UUID, text: String, selection: NSRange) -> TaskContinuation {
        guard let n = notes.firstIndex(where: { $0.id == noteID }),
              let t = notes[n].tasks.firstIndex(where: { $0.id == taskID }) else { return .ignored }
        let contents = text as NSString
        guard selection.location >= 0, selection.location != NSNotFound, selection.location <= contents.length,
              selection.length >= 0, selection.length <= contents.length - selection.location else { return .ignored }
        var tasks = notes[n].tasks
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tasks.remove(at: t)
            notes[n].tasks = tasks
            saveNotes()
            return .finished
        }
        // Native text selections use UTF-16, including for emoji and Chinese.
        // Enter replaces a selection and moves the remaining suffix below it.
        let prefix = contents.substring(to: selection.location)
        let next = NoteTask(text: contents.substring(from: NSMaxRange(selection)))
        tasks[t].text = prefix
        tasks.insert(next, at: t + 1)
        notes[n].tasks = tasks
        saveNotes()
        return .inserted(id: next.id, prefix: prefix)
    }
    func removeTask(_ taskID: UUID, from noteID: UUID) {
        guard let n = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[n].tasks.removeAll { $0.id == taskID }
        saveNotes()
    }
    func moveNote(_ id: UUID, to position: CGPoint) {
        guard position.x.isFinite, position.y.isFinite,
              let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].x = Double(position.x); notes[index].y = Double(position.y)
        let clamped = notePosition(notes[index], index: index, width: max(viewportWidth, contentWidth + 40))
        notes[index].x = Double(clamped.x); notes[index].y = Double(clamped.y)
        saveNotes(); onLayoutChange()
    }
    func resizeNote(_ id: UUID, to size: CGSize) {
        guard size.width.isFinite, size.height.isFinite,
              let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let bounded = CardSizing.noteSize(size, available: availableSize)
        notes[index].width = Double(bounded.width)
        notes[index].height = Double(bounded.height)
        saveNotes(); onLayoutChange()
    }
    func removeNote(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        lastRemovedNote = note
        defaults.set(try? JSONEncoder().encode(note), forKey: "lastRemovedNote")
        notes.removeAll { $0.id == id }
        if editingNoteID == id { editingNoteID = nil; onFinishNoteEditing() }
        if noteFocusRequest == id { noteFocusRequest = nil }
        saveNotes(); onLayoutChange()
    }
    func resetNotePosition(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].x = nil; notes[index].y = nil
        saveNotes(); onLayoutChange()
    }
    func restoreLastNote() {
        guard let note = lastRemovedNote, !notes.contains(where: { $0.id == note.id }) else { return }
        notes.append(note)
        lastRemovedNote = nil
        defaults.removeObject(forKey: "lastRemovedNote")
        saveNotes(); onLayoutChange()
    }
    private func saveNotes() { defaults.set(try? JSONEncoder().encode(notes), forKey: "stickyNotes") }

    /// Moves the file to the Trash and takes the photo off the line. When a
    /// drag ends on the Dock's Trash, macOS only reports it: deleting the file
    /// is the source app's job, as Finder does.
    func trash(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            log.notice("Trashed \(item.url.lastPathComponent, privacy: .public)")
            if soundOn { Line.trashSound?.play() }
            drop(id, quietly: true)
        } catch {
            log.error("Could not trash \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    /// Taking an image down never deletes a file, regardless of its source.
    func discard(_ id: UUID) {
        drop(id)
    }

    /// Export a copy, leaving both the original and the hanging image intact.
    func copyToDesktop(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let target = uniqueURL(in: desktop, for: item.url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: item.url, to: target)
        } catch {
            log.error("Could not save to Desktop: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Long press: open the photo in the system Markup editor.
    func markup(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        Markup.shared.edit(item.url)
    }

    /// After editing, the photo on the line shows the new version.
    func reloadThumbnail(for url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url, maxPixels: max(thumbnailLimits[items[i].id] ?? 480,
                                                           CardSizing.thumbnailPixels(scale: items[i].scale))) else { return }
        items[i].thumb = thumb
        modificationDates[url.path] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Breeze

    /// Every so often a little wind moves the line. It is the detail that
    /// makes it feel like an object and not a widget.
    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Persistence

    private func save() {
        let paths = items.filter { !$0.falling }.map(\.url.path)
        defaults.set(paths, forKey: storeKey)
        let scales = Dictionary(uniqueKeysWithValues: items.filter { !$0.falling }.map {
            ($0.url.imageIdentityPath, Double($0.scale))
        })
        defaults.set(scales, forKey: "peggedScales")
        savedScales.merge(scales) { _, new in new }
        let positions = Dictionary(uniqueKeysWithValues: items.filter { !$0.falling }.compactMap { item -> (String, [Double])? in
            guard let position = item.hangingPosition else { return nil }
            return (item.url.imageIdentityPath, [Double(position.x), Double(position.y)])
        })
        defaults.set(positions, forKey: "peggedPositions")
        savedPositions.merge(positions) { _, new in new }
    }

    private func restore() {
        let paths = defaults.stringArray(forKey: storeKey) ?? []
        for path in paths where FileManager.default.fileExists(atPath: path) {
            hang(URL(fileURLWithPath: path), quietly: true)
        }
    }

    // MARK: Helpers

    private func play(_ name: String, volume: Float) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

func makeThumbnail(_ url: URL, maxPixels: Int = 480) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
