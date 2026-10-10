import AppKit
import XCTest
import SwiftUI
@testable import Pinloom

final class WorkflowTests: XCTestCase {
    @MainActor
    func testTaskReturnInsertsBelowAndSplitsUnicodeSelectionWithoutCompletingTheNewTask() throws {
        let line = Line(defaults: defaults)
        let note = line.addNote()
        let first = try XCTUnwrap(line.addTask(to: note))
        let following = try XCTUnwrap(line.addTask(to: note))
        line.setTask(first, in: note, text: "Old stored value", completed: true)
        line.setTask(following, in: note, text: "Keep this next")
        let liveText = "整理🧠截图，提交方案"
        let splitPoint = ("整理🧠截图" as NSString).length
        guard case .inserted(let created, let prefix) = line.continueTask(first, in: note, text: liveText,
                                                                         selection: NSRange(location: splitPoint, length: 1)) else {
            return XCTFail("Return should split the live field editor's text")
        }
        let tasks = try XCTUnwrap(line.notes.first?.tasks)
        XCTAssertEqual(prefix, "整理🧠截图")
        XCTAssertEqual(tasks.map(\.id), [first, created, following])
        XCTAssertEqual(tasks.map(\.text), ["整理🧠截图", "提交方案", "Keep this next"])
        XCTAssertEqual(tasks.map(\.completed), [true, false, false])
        XCTAssertEqual(Line(defaults: defaults).notes.first?.tasks, tasks)
        guard case .inserted(let next, _) = line.continueTask(created, in: note, text: "提交方案",
                                                            selection: NSRange(location: 4, length: 0)) else {
            return XCTFail("Return at the end should create an empty next task")
        }
        XCTAssertEqual(line.notes.first?.tasks.map(\.id), [first, created, next, following])
        XCTAssertEqual(line.notes.first?.tasks[2].text, "")
    }

    @MainActor
    func testNativeTaskReturnIgnoresMarkedTextAndEndsEditingOnAnEmptyTask() throws {
        let line = Line(defaults: defaults)
        let note = line.addNote()
        let task = try XCTUnwrap(line.addTask(to: note))
        line.setTask(task, in: note, text: "First task")
        var finished = 0
        line.onFinishNoteEditing = { finished += 1 }
        let body = StickyNoteBody(frame: NSRect(x: 0, y: 0, width: 320, height: 280))
        body.configure(note: try XCTUnwrap(line.notes.first), line: line)
        body.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let field = try XCTUnwrap(descendants(body).compactMap { $0 as? NSTextField }.first { $0.stringValue == "First task" })
        let editor = NSTextView()
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), false)
        XCTAssertEqual(line.notes.first?.tasks.count, 1)
        editor.unmarkText()
        editor.string = "First task"
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        XCTAssertEqual(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), true)
        XCTAssertEqual(line.notes.first?.tasks.count, 2)
        XCTAssertEqual(line.editingNoteID, note, "Return must establish editing ownership even before any typing")
        body.layoutSubtreeIfNeeded()
        let emptyField = try XCTUnwrap(descendants(body).compactMap { $0 as? NSTextField }.first { $0.placeholderString == L("To-do") && $0.stringValue.isEmpty })
        editor.string = "  "
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertEqual(emptyField.delegate?.control?(emptyField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), true)
        XCTAssertEqual(line.notes.first?.tasks.map(\.id), [task])
        XCTAssertEqual(Line(defaults: defaults).notes.first?.tasks.map(\.text), ["First task"])
        XCTAssertNil(line.editingNoteID)
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(line.continueTask(task, in: note, text: "First task", selection: NSRange(location: NSNotFound, length: 0)), .ignored)
        XCTAssertEqual(line.notes.first?.tasks.count, 1)
    }

    @MainActor
    func testLargeCardsFitTheScreenWithoutLosingSavedSizesOnSmallerDisplays() throws {
        let source = try image("readable-default")
        let original = try Data(contentsOf: source)
        let line = Line(defaults: defaults)
        let id = try XCTUnwrap(line.hang(source, quietly: true))
        XCTAssertEqual(line.items.first?.scale, 2.25)
        line.resize(id, scale: 100)
        let requested = try XCTUnwrap(line.items.first?.scale)
        XCTAssertGreaterThan(requested, 3)
        let noteID = line.addNote()
        line.resizeNote(noteID, to: CGSize(width: 700, height: 700))
        XCTAssertEqual(Line(defaults: defaults).notes.first?.width, 700)
        let saved = defaults.dictionaryRepresentation()
        line.viewportWidth = 800; line.availableHeight = 600
        let rendered = try XCTUnwrap(line.displayItems.first)
        let card = PeggedView.cardSize(for: rendered.thumb.size, scale: rendered.scale)
        XCTAssertLessThanOrEqual(card.width, 640.001)
        XCTAssertLessThanOrEqual(card.height, 500.001)
        XCTAssertLessThanOrEqual(line.noteSize(try XCTUnwrap(line.notes.first)).height, 500)
        XCTAssertEqual(line.items.first?.scale, requested)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, saved as NSDictionary)
        line.viewportWidth = 1440; line.availableHeight = 900
        XCTAssertEqual(line.displayItems.first?.scale, requested)
        XCTAssertEqual(Line(defaults: defaults).items.first?.scale, requested)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    @MainActor
    func testTaskOnlyNotesKeepTasksNearTheHeaderAndLongContentSharesOneScrollArea() throws {
        let line = Line(defaults: defaults)
        let id = line.addNote()
        let task = try XCTUnwrap(line.addTask(to: id))
        line.setTask(task, in: id, text: "Review screenshots")
        let body = StickyNoteBody()
        body.configure(note: try XCTUnwrap(line.notes.first), line: line)
        body.setFrameSize(NSSize(width: 320, height: 580))
        body.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(body).first { $0 is NoteTextView } as? NoteTextView)
        let checkbox = try XCTUnwrap(descendants(body).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Review screenshots" })
        XCTAssertLessThan(checkbox.convert(checkbox.bounds, to: body).minY, 110)
        XCTAssertEqual(descendants(body).filter { $0 is NSScrollView }.count, 1)
        line.setNoteText(id, text: Array(repeating: "A long note with editable content", count: 30).joined(separator: "\n"))
        body.configure(note: try XCTUnwrap(line.notes.first), line: line)
        body.layoutSubtreeIfNeeded()
        let textBottom = editor.convert(editor.bounds, to: body).maxY
        XCTAssertGreaterThan(textBottom, body.bounds.height)
        XCTAssertGreaterThan(checkbox.convert(checkbox.bounds, to: body).minY, textBottom)
        XCTAssertGreaterThan(editor.enclosingScrollView?.documentView?.frame.height ?? 0,
                             editor.enclosingScrollView?.contentSize.height ?? 0)
    }

    @MainActor
    func testNotePresentationAtMinimumDefaultAndLargeSizes() async throws {
        let line = Line(defaults: defaults)
        let sizes = [CGSize(width: 240, height: 220), CGSize(width: 320, height: 280), CGSize(width: 600, height: 480)]
        var notes: [StickyNote] = []
        for (index, size) in sizes.enumerated() {
            let id = line.addNote()
            if index > 0 { line.setNoteText(id, text: "今天要完成的事情\nKeep the reference close.") }
            for (text, complete) in [("Review screenshots", false), ("Update the design", true)] {
                let task = try XCTUnwrap(line.addTask(to: id))
                line.setTask(task, in: id, text: text, completed: complete)
            }
            line.resizeNote(id, to: size)
            notes.append(try XCTUnwrap(line.notes.last))
        }
        let preview = HStack(alignment: .top, spacing: 24) {
            ForEach(notes) { note in
                StickyNoteCard(note: note, line: line, anchor: .zero)
            }
        }.padding(24).background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: preview)
        host.setFrameSize(NSSize(width: 1340, height: 560))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for body in descendants(host).compactMap({ $0 as? StickyNoteBody }) {
            let copy = try XCTUnwrap(descendants(body).compactMap { $0 as? NSButton }.first { $0.toolTip == L("Copy note") })
            XCTAssertTrue(body.bounds.contains(copy.frame))
            let scroll = try XCTUnwrap(descendants(body).first { $0 is NSScrollView } as? NSScrollView)
            XCTAssertTrue(body.bounds.contains(scroll.frame))
        }
        if let path = ProcessInfo.processInfo.environment["PINLOOM_NOTE_GRID_PREVIEW"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    func testBrandMigrationCopiesImagesNotesReferencesAndLayoutWithoutChangingOriginals() throws {
        let legacyName = suite + ".legacy"
        let legacy = UserDefaults(suiteName: legacyName)!
        defer { legacy.removePersistentDomain(forName: legacyName) }
        legacy.set(true, forKey: "soundOff")
        let support = directory.appendingPathComponent("Support", isDirectory: true)
        let oldImports = support.appendingPathComponent("Tendedero/Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: oldImports, withIntermediateDirectories: true)
        let original = oldImports.appendingPathComponent("saved.png")
        let contents = try Data(contentsOf: image("migration-source"))
        try contents.write(to: original)
        let oldLine = Line(defaults: legacy)
        let imageID = try XCTUnwrap(oldLine.hang(original, quietly: true))
        oldLine.resize(imageID, scale: 2)
        oldLine.move(imageID, to: CGPoint(x: 800, y: 200))
        let oldCaptures = support.appendingPathComponent("Tendedero/Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: oldCaptures, withIntermediateDirectories: true)
        let capture = oldCaptures.appendingPathComponent("saved.png") // Same name, separate private source folder.
        try contents.write(to: capture)
        _ = oldLine.hang(capture, quietly: true)
        let noteID = oldLine.addNote()
        oldLine.setNoteText(noteID, text: "迁移后继续使用")
        let task = try XCTUnwrap(oldLine.addTask(to: noteID))
        oldLine.setTask(task, in: noteID, text: "Finish the release", completed: true)
        let oldLibrary = ReferenceLibrary(folder: support.appendingPathComponent("Tendedero/References"), defaults: legacy)
        let record = try oldLibrary.pin(original)
        let before = legacy.dictionaryRepresentation()
        try LegacyDataMigration.run(defaults: defaults, legacy: legacy, support: support)
        let migrated = Line(defaults: defaults)
        let imported = try XCTUnwrap(migrated.items.first)
        XCTAssertEqual(imported.url.path, support.appendingPathComponent("Pinloom/Imports/saved.png").path)
        XCTAssertEqual(try Data(contentsOf: imported.url), contents)
        XCTAssertEqual(imported.scale, 2)
        XCTAssertEqual(imported.hangingPosition, oldLine.items.first?.hangingPosition)
        XCTAssertEqual(migrated.items.count, 2)
        XCTAssertEqual(migrated.items.last?.url.path, support.appendingPathComponent("Pinloom/LegacyImages/saved.png").path)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(migrated.items.last?.url)), contents)
        XCTAssertEqual(migrated.notes, oldLine.notes)
        let library = ReferenceLibrary(folder: support.appendingPathComponent("Pinloom/References"), defaults: defaults)
        XCTAssertEqual(library.records.first?.sourcePath, imported.url.path)
        XCTAssertEqual(try Data(contentsOf: library.url(for: record)), contents)
        XCTAssertEqual(try Data(contentsOf: original), contents)
        XCTAssertEqual(legacy.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertTrue(defaults.bool(forKey: LegacyDataMigration.completedKey))
        let extra = migrated.addNote()
        oldLine.setNoteText(noteID, text: "Old app changed independently")
        try LegacyDataMigration.run(defaults: defaults, legacy: legacy, support: support)
        XCTAssertEqual(Line(defaults: defaults).notes.map(\.id), [noteID, extra])
        XCTAssertEqual(Line(defaults: defaults).notes.first?.text, "迁移后继续使用")
    }

    @MainActor
    func testBrandMigrationNeverOverwritesExistingPinloomData() throws {
        let legacyName = suite + ".legacy"
        let legacy = UserDefaults(suiteName: legacyName)!
        defer { legacy.removePersistentDomain(forName: legacyName) }
        let line = Line(defaults: defaults)
        let id = line.addNote()
        line.setNoteText(id, text: "My new workspace")
        legacy.set(["old.png"], forKey: "pegged")
        try LegacyDataMigration.run(defaults: defaults, legacy: legacy, support: directory)
        XCTAssertNil(defaults.stringArray(forKey: "pegged"))
        XCTAssertEqual(Line(defaults: defaults).notes.first?.text, "My new workspace")
    }

    func testBrandMigrationRetriesFailedCopiesBeforeCommittingPreferences() throws {
        let legacyName = suite + ".legacy"
        let legacy = UserDefaults(suiteName: legacyName)!
        defer { legacy.removePersistentDomain(forName: legacyName) }
        let old = directory.appendingPathComponent("Tendedero/Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let original = old.appendingPathComponent("image.png")
        try Data("source data".utf8).write(to: original)
        legacy.set([original.path], forKey: "pegged")
        let blocker = directory.appendingPathComponent("Pinloom")
        try Data("not a folder".utf8).write(to: blocker)
        XCTAssertThrowsError(try LegacyDataMigration.run(defaults: defaults, legacy: legacy, support: directory))
        XCTAssertFalse(defaults.bool(forKey: LegacyDataMigration.completedKey))
        XCTAssertNil(defaults.stringArray(forKey: "pegged"))
        try FileManager.default.removeItem(at: blocker)
        try LegacyDataMigration.run(defaults: defaults, legacy: legacy, support: directory)
        XCTAssertEqual(defaults.stringArray(forKey: "pegged"), [directory.appendingPathComponent("Pinloom/Imports/image.png").path])
        XCTAssertEqual(try String(contentsOf: original), "source data")
    }

    @MainActor
    func testMenuOnlyShowsManualActionsAndContextualRecovery() throws {
        let line = Line(defaults: defaults)
        let library = ReferenceLibrary(folder: directory.appendingPathComponent("References"), defaults: defaults)
        let app = AppDelegate(line: line, references: ReferenceImages(library: library))
        let menu = NSMenu()
        app.menuNeedsUpdate(menu)
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, [L("Show line"), L("Paste image"), L("Add images…"), L("New note"), L("Options"), L("Quit Pinloom")])
        XCTAssertEqual(menu.items.first { $0.title == L("Options") }?.submenu?.items.map(\.title), [L("Sounds"), L("Open at login")])
        let id = line.addNote()
        line.removeNote(id)
        app.menuNeedsUpdate(menu)
        XCTAssertNotNil(menu.items.first { $0.title == L("Restore last note") })
        line.restoreLastNote()
        line.setShown(true)
        _ = try library.pin(try image("menu-reference"))
        app.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items.first?.title, L("Hide line"))
        XCTAssertNil(menu.items.first { $0.title == L("Restore last note") })
        XCTAssertNotNil(menu.items.first { $0.title == L("Hide reference images") })
        XCTAssertNotNil(menu.items.first { $0.title == L("Arrange") }?.submenu)
    }

    func testLegacyScreenshotCleanupRestoresOnlyOwnedSettingsOnce() {
        // A file URL inferred from a missing path lacks the directory slash.
        // Ownership must compare normalized paths, regardless of existence.
        let ownedFolder = directory.appendingPathComponent("NeverCreated/Screenshots", isDirectory: true)
        let folder = ownedFolder.path
        defaults.set(["location": "/previous", "thumbnail": true], forKey: "inboxSavedSettings")
        defaults.set(true, forKey: "inboxEnabled")
        var values: [String: Any] = ["location": folder, "location-screenshot": folder, "show-thumbnail": false]
        var writes = 0
        let write: (String, Any?) -> Void = { values[$0] = $1; writes += 1 }
        LegacyScreenshotSettings.restoreIfNeeded(defaults: defaults, ownedFolder: ownedFolder, read: { values[$0] }, write: write)
        XCTAssertEqual(values["location"] as? String, "/previous")
        XCTAssertNil(values["location-screenshot"])
        XCTAssertEqual(values["show-thumbnail"] as? Bool, true)
        XCTAssertNil(defaults.dictionary(forKey: "inboxSavedSettings"))
        XCTAssertFalse(defaults.bool(forKey: "inboxEnabled"))
        XCTAssertEqual(writes, 3)
        LegacyScreenshotSettings.restoreIfNeeded(defaults: defaults, ownedFolder: ownedFolder, read: { values[$0] }, write: write)
        XCTAssertEqual(writes, 3)
    }

    func testLegacyScreenshotCleanupLeavesUserChangesAndFreshInstallsAlone() {
        var reads = 0
        LegacyScreenshotSettings.restoreIfNeeded(defaults: defaults, read: { _ in reads += 1; return nil },
                                                 write: { _, _ in XCTFail("Fresh installs must not write system preferences") })
        XCTAssertEqual(reads, 0)
        defaults.set(["location": "/previous", "thumbnail": true], forKey: "inboxSavedSettings")
        let external: [String: Any] = ["location": "/user-chosen", "location-screenshot": "/user-chosen", "show-thumbnail": false]
        LegacyScreenshotSettings.restoreIfNeeded(defaults: defaults, read: { external[$0] },
                                                 write: { _, _ in XCTFail("Do not overwrite changes made outside Pinloom") })
        XCTAssertNil(defaults.dictionary(forKey: "inboxSavedSettings"))
    }

    @MainActor
    func testNoteCopyCommandsUseSelectionAndWholeNoteCopyIncludesLiveTasks() throws {
        let line = Line(defaults: defaults)
        let id = line.addNote()
        line.setNoteText(id, text: "正文可以复制")
        let task = try XCTUnwrap(line.addTask(to: id))
        line.setTask(task, in: id, text: "完成报告", completed: true)
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        let generalCount = NSPasteboard.general.changeCount
        let body = StickyNoteBody(clipboard: clipboard)
        body.configure(note: try XCTUnwrap(line.notes.first), line: line)
        body.setFrameSize(NSSize(width: 300, height: 300))
        let panel = LinePanel(content: body) // Never ordered onscreen or made key.
        defer { panel.close() }
        panel.setFrame(NSRect(x: 0, y: 0, width: 300, height: 300), display: false)
        body.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(body).first { $0 is NoteTextView } as? NoteTextView)
        func command(_ key: String) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0))
        }
        XCTAssertTrue(panel.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        XCTAssertTrue(panel.performKeyEquivalent(with: try command("c")))
        XCTAssertEqual(clipboard.string(forType: .string), "正文")
        XCTAssertTrue(panel.performKeyEquivalent(with: try command("a")))
        XCTAssertEqual(editor.selectedRange().length, (editor.string as NSString).length)
        XCTAssertTrue(editor.performKeyEquivalent(with: try command("c")))
        XCTAssertEqual(clipboard.string(forType: .string), "正文可以复制")
        // Standard shared field editors use the same window routing.
        editor.isFieldEditor = true
        editor.string = "待办也可以复制"
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        XCTAssertTrue(panel.performKeyEquivalent(with: try command("c")))
        XCTAssertEqual(clipboard.string(forType: .string), "待办")
        let copy = try XCTUnwrap(descendants(body).compactMap { $0 as? NSButton }.first { $0.toolTip == L("Copy note") })
        // This change deliberately happens before SwiftUI reconfigures the view.
        line.setNoteText(id, text: "最新正文")
        line.setTask(task, in: id, completed: false)
        copy.performClick(nil)
        XCTAssertEqual(clipboard.string(forType: .string), "最新正文\n[ ] 完成报告")
        XCTAssertEqual(NSPasteboard.general.changeCount, generalCount)
        XCTAssertFalse(NoteEditingCommands.perform(try command("c"), on: NSResponder()))
    }

    @MainActor
    func testPlainNoteUsesAvailableSpaceAndEditMenuProvidesNativeResponderActions() throws {
        let line = Line(defaults: defaults)
        _ = line.addNote()
        let body = StickyNoteBody()
        body.configure(note: try XCTUnwrap(line.notes.first), line: line)
        body.setFrameSize(NSSize(width: 240, height: 400))
        body.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(body).first { $0 is NoteTextView } as? NoteTextView)
        XCTAssertGreaterThan(editor.enclosingScrollView?.frame.height ?? 0, 300)
        let actions = NoteEditingCommands.menu().items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(actions.map(\.keyEquivalent), ["z", "z", "x", "c", "v", "a"])
        XCTAssertTrue(actions.allSatisfy { $0.target == nil && $0.action != nil })
        XCTAssertEqual(actions[1].keyEquivalentModifierMask, [.command, .shift])
    }

    @MainActor
    func testNewNoteFocusRequestScrollsAnOverflowingLineToTheNote() async throws {
        let line = Line(defaults: defaults)
        line.viewportWidth = 800; line.availableHeight = 600
        for _ in 0..<5 { _ = line.addNote() }
        line.revealed = true
        let host = NSHostingView(rootView: LineView(line: line))
        host.sizingOptions = []
        let panel = LinePanel(content: host)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 0, y: 0, width: 800, height: 350), display: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        func bodies(_ view: NSView) -> [StickyNoteBody] {
            (view as? StickyNoteBody).map { [$0] } ?? view.subviews.flatMap(bodies)
        }
        let last = try XCTUnwrap(bodies(host).max { $0.convert($0.bounds, to: host).maxX < $1.convert($1.bounds, to: host).maxX })
        XCTAssertFalse(host.bounds.intersects(last.convert(last.bounds, to: host)))
        line.noteFocusRequest = line.notes.last?.id
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.bounds.intersects(last.convert(last.bounds, to: host)), "New notes should be brought into view before editing")
    }

    func testNotesRememberTextTasksCompletionAndLayoutAcrossRelaunch() async throws {
        try await MainActor.run {
            let line = Line(defaults: defaults)
            line.viewportWidth = 1200; line.availableHeight = 800
            let id = line.addNote()
            line.setNoteText(id, text: "今天要完成的事情\nRemember the design review")
            let first = try XCTUnwrap(line.addTask(to: id))
            let second = try XCTUnwrap(line.addTask(to: id))
            line.setTask(first, in: id, text: "整理截图", completed: true)
            line.setTask(second, in: id, text: "提交方案", completed: false)
            line.moveNote(id, to: CGPoint(x: 750, y: 240))
            line.resizeNote(id, to: CGSize(width: 320, height: 360))
            let restored = Line(defaults: defaults)
            XCTAssertEqual(restored.notes, line.notes)
            XCTAssertEqual(restored.notes.first?.tasks.map(\.completed), [true, false])
            restored.setTask(first, in: id, completed: false)
            XCTAssertEqual(Line(defaults: defaults).notes.first?.tasks.first?.completed, false)
            restored.removeTask(second, from: id)
            XCTAssertEqual(Line(defaults: defaults).notes.first?.tasks.map(\.id), [first])
        }
    }

    func testManualImportsAndClearingImagesNeverRemoveNotes() async throws {
        let sources = try (0..<4).map { try image("overflow-note-\($0)") }
        await MainActor.run {
            let line = Line(defaults: defaults)
            let id = line.addNote()
            line.setNoteText(id, text: "Keep this reminder")
            for source in sources { _ = line.hang(source, quietly: true) }
            XCTAssertEqual(line.liveCount, 4)
            XCTAssertEqual(line.notes.map(\.id), [id])
            for image in line.items where !image.falling { line.drop(image.id, quietly: true) }
            XCTAssertEqual(line.totalCount, 1)
            XCTAssertEqual(Line(defaults: defaults).notes.first?.text, "Keep this reminder")
        }
    }

    func testRemovedNoteCanBeRestoredIncludingAfterRelaunchAndResizeIsBounded() async throws {
        try await MainActor.run {
            let line = Line(defaults: defaults)
            let id = line.addNote()
            line.setNoteText(id, text: "Important reminder")
            line.resizeNote(id, to: CGSize(width: -200, height: 4000))
            XCTAssertEqual(line.notes.first?.width, 240)
            XCTAssertEqual(line.notes.first?.height, 800)
            line.resizeNote(id, to: CGSize(width: CGFloat.infinity, height: CGFloat.nan))
            XCTAssertEqual(line.notes.first?.width, 240)
            line.removeNote(id)
            let restored = Line(defaults: defaults)
            XCTAssertTrue(restored.notes.isEmpty)
            restored.restoreLastNote()
            restored.restoreLastNote()
            XCTAssertEqual(restored.notes.count, 1)
            XCTAssertEqual(restored.notes.first?.text, "Important reminder")
            XCTAssertNil(restored.lastRemovedNote)
            XCTAssertEqual(Line(defaults: defaults).notes.first?.id, id)
            restored.moveNote(id, to: CGPoint(x: -1000, y: -1000))
            let note = try XCTUnwrap(restored.notes.first)
            XCTAssertGreaterThan(note.x ?? 0, 0)
            XCTAssertGreaterThanOrEqual(note.y ?? -1, 0)
        }
    }

    @MainActor
    func testNoteEditorRoutesTextAndCheckboxChangesAndNativeHitTargets() async throws {
        let line = Line(defaults: defaults)
        line.viewportWidth = 900; line.availableHeight = 700
        let id = line.addNote()
        let taskID = try XCTUnwrap(line.addTask(to: id))
        line.setTask(taskID, in: id, text: "Review screenshots")
        line.moveNote(id, to: CGPoint(x: 350, y: 85))
        line.revealed = true
        let host = NSHostingView(rootView: LineView(line: line))
        host.sizingOptions = []
        let panel = LinePanel(content: host)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 0, y: 0, width: 900, height: 400), display: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(host)
        let body = try XCTUnwrap(views.first { $0 is StickyNoteBody } as? StickyNoteBody)
        let resize = try XCTUnwrap(views.first { $0 is NoteResizeView })
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(GrabView().needsPanelToBecomeKey)
        XCTAssertFalse(LineImportView().needsPanelToBecomeKey)
        for target in [body, resize] {
            let point = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
            XCTAssertTrue(panel.interactiveView(atWindowPoint: point) === target)
        }
        let editor = try XCTUnwrap(views.first { $0 is NSTextView } as? NSTextView)
        XCTAssertTrue(editor.needsPanelToBecomeKey)
        editor.string = "新的便签内容"
        editor.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertEqual(line.notes.first?.text, "新的便签内容")
        let checkbox = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Review screenshots" })
        checkbox.performClick(nil)
        XCTAssertEqual(line.notes.first?.tasks.first?.completed, true)
        XCTAssertEqual(Line(defaults: defaults).notes.first?.tasks.first?.completed, true)
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        if let path = ProcessInfo.processInfo.environment["PINLOOM_NOTE_PREVIEW"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
    }

    func testImportButtonsResolveTheirActionsAfterViewCreation() async {
        await MainActor.run {
            let line = Line(defaults: defaults)
            let paste = LineImportView(frame: NSRect(x: 0, y: 0, width: 100, height: 26))
            let files = LineImportView(frame: NSRect(x: 0, y: 0, width: 100, height: 26))
            paste.configure(line: line, action: .clipboard)
            files.configure(line: line, action: .files)
            var pasted = 0
            var picked = 0
            line.onPasteImage = { pasted += 1 }
            line.onChooseImages = { picked += 1 }
            XCTAssertTrue(paste.accessibilityPerformPress())
            XCTAssertEqual(pasted, 1)
            XCTAssertEqual(picked, 0)
            XCTAssertTrue(files.accessibilityPerformPress())
            XCTAssertEqual(pasted, 1)
            XCTAssertEqual(picked, 1)
            let noteButton = LineImportView(frame: NSRect(x: 0, y: 0, width: 100, height: 26))
            noteButton.configure(line: line, action: .note)
            line.onCreateNote = { _ = line.addNote() }
            XCTAssertTrue(noteButton.accessibilityPerformPress())
            XCTAssertEqual(line.notes.count, 1)
            XCTAssertEqual(pasted, 1)
            XCTAssertEqual(picked, 1)
        }
    }

    @MainActor
    func testEmptyLineHasNativeImportTargetsAndKeepsBackgroundClicksPassingThrough() async throws {
        let line = Line(defaults: defaults)
        line.revealed = true
        let host = NSHostingView(rootView: LineView(line: line))
        host.sizingOptions = []
        let panel = LinePanel(content: host)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 0, y: 0, width: 800, height: 210), display: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        func targets(in view: NSView) -> [LineImportView] {
            (view as? LineImportView).map { [$0] } ?? view.subviews.flatMap { targets(in: $0) }
        }
        let imports = targets(in: host)
        XCTAssertEqual(imports.count, 4, "Paste, picker, note creation, and the empty drop area must be directly reachable")
        for target in imports {
            let center = NSPoint(x: target.bounds.midX, y: target.bounds.midY)
            XCTAssertTrue(panel.interactiveView(atWindowPoint: target.convert(center, to: nil)) === target)
        }
        XCTAssertTrue(imports.contains { $0.bounds.width >= 300 && $0.bounds.height >= 70 })
        XCTAssertNil(panel.interactiveView(atWindowPoint: NSPoint(x: 10, y: 50)))
        if let path = ProcessInfo.processInfo.environment["PINLOOM_IMPORT_PREVIEW"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    func testHideControlUsesHandlerInstalledAfterViewCreationAndKeepsNotes() async {
        await MainActor.run {
            let line = Line(defaults: defaults)
            let id = line.addNote()
            line.setNoteText(id, text: "Remember this")
            line.setShown(true)
            line.editingNoteID = id
            line.noteFocusRequest = id
            let control = LineDismissView(frame: NSRect(x: 0, y: 0, width: 100, height: 26))
            control.configure(line: line)
            line.onHideLine = { line.setShown(false) }
            XCTAssertFalse(control.needsPanelToBecomeKey)
            XCTAssertTrue(control.acceptsFirstMouse(for: nil))
            XCTAssertTrue(control.accessibilityPerformPress())
            XCTAssertFalse(line.revealed)
            XCTAssertNil(line.editingNoteID)
            XCTAssertNil(line.noteFocusRequest)
            XCTAssertEqual(line.notes.first?.text, "Remember this")
            line.setShown(true)
            XCTAssertTrue(control.accessibilityPerformPress())
            XCTAssertFalse(line.revealed)
        }
    }

    @MainActor
    func testRenderedHideControlIsHitTestableBeforeGeometryPreferencesArrive() async throws {
        let line = Line(defaults: defaults)
        let imageID = try XCTUnwrap(line.hang(try image("hit-test"), quietly: true))
        line.viewportWidth = 800
        line.availableHeight = 210
        // Keep both native image controls inside the canvas even during the
        // initial arrival offset; the test window is never ordered onscreen.
        line.move(imageID, to: CGPoint(x: 260, y: 90))
        line.revealed = true
        let host = NSHostingView(rootView: LineView(line: line))
        host.sizingOptions = []
        let panel = LinePanel(content: host)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 0, y: 0, width: 800, height: 210), display: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        func control(in view: NSView) -> LineDismissView? {
            if let found = view as? LineDismissView { return found }
            return view.subviews.compactMap { control(in: $0) }.first
        }
        let button = try XCTUnwrap(control(in: host))
        XCTAssertGreaterThanOrEqual(button.bounds.width, 90)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 22)
        let buttonPoint = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
        XCTAssertTrue(panel.interactiveView(atWindowPoint: button.convert(buttonPoint, to: nil)) === button)
        XCTAssertNil(panel.interactiveView(atWindowPoint: NSPoint(x: 10, y: 50)))
        let point = button.convert(buttonPoint, to: host.superview)
        var hit = host.hitTest(point)
        while hit != nil && hit !== button { hit = hit?.superview }
        XCTAssertTrue(hit === button, "The native control must receive hits rather than the scroll view behind it")
        func descendants(of view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { descendants(of: $0) }
        }
        let views = descendants(of: host)
        let card = try XCTUnwrap(views.first { $0 is GrabView })
        let clip = try XCTUnwrap(views.first { $0 is ClipMoveView })
        for target in [card, clip] {
            let center = NSPoint(x: target.bounds.midX, y: target.bounds.midY)
            XCTAssertTrue(panel.interactiveView(atWindowPoint: target.convert(center, to: nil)) === target,
                          "Native hit routing must preserve \(type(of: target)) at \(target.convert(center, to: nil))")
        }
    }

    func testDraggedImageSwingsInDirectionOfInertiaAndSettlesAfterRelease() {
        var motion = HangingDynamics()
        motion.drive(velocity: 450)
        motion.advance(by: 0.08)
        XCTAssertGreaterThan(motion.angle, 0, "Moving the clip right should leave the image leaning left")
        let initialAngle = motion.angle
        motion.drive(velocity: 0)
        var crossesRest = false
        for _ in 0..<600 {
            motion.advance(by: 1.0 / 60)
            if motion.angle * initialAngle < 0 { crossesRest = true }
        }
        XCTAssertTrue(crossesRest, "The image should sway back past rest instead of snapping to it")
        XCTAssertTrue(motion.settled)
        XCTAssertEqual(motion.angle, 0)
    }

    func testRapidDragReversalsAndDelayedFramesKeepSwingBounded() {
        var motion = HangingDynamics()
        for index in 0..<120 {
            motion.drive(velocity: index.isMultiple(of: 2) ? 50_000 : -50_000)
            motion.advance(by: index.isMultiple(of: 3) ? 0.5 : 1.0 / 60)
            XCTAssertTrue(motion.angle.isFinite)
            XCTAssertLessThanOrEqual(abs(motion.angle), 0.42)
        }
        motion.drive(velocity: 0)
        for _ in 0..<600 { motion.advance(by: 1.0 / 60) }
        XCTAssertTrue(motion.settled)
    }

    func testResizeCursorRegionMatchesBottomCornerWithoutOverlappingPin() async {
        await MainActor.run {
            for height: CGFloat in [48, 80, 320] {
                let bounds = NSRect(x: 0, y: 0, width: 160, height: height)
                for flipped in [true, false] {
                    let corner = GrabView.resizeRect(in: bounds, flipped: flipped)
                    let bottom = CGPoint(x: 155, y: flipped ? height - 3 : 3)
                    let top = CGPoint(x: 155, y: flipped ? 3 : height - 3)
                    XCTAssertTrue(corner.contains(bottom))
                    XCTAssertFalse(corner.contains(top))
                    XCTAssertTrue(bounds.contains(corner))
                }
            }
        }
    }

    func testUnfocusedImageUsesNativeResizeCursorOnlyAtResizeCorner() async {
        await MainActor.run {
            // No window, application activation, or cursor.set(): this tests
            // hover selection without touching the user's live pointer.
            let view = GrabView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
            XCTAssertNil(view.window)
            let corner = CGPoint(x: 155, y: view.isFlipped ? 77 : 3)
            let center = CGPoint(x: 80, y: 40)
            XCTAssertTrue(view.cursor(at: center) === NSCursor.arrow)
            XCTAssertFalse(view.cursor(at: corner) === NSCursor.arrow)
            if #available(macOS 15.0, *) {
                let native = NSCursor.frameResize(position: .bottomRight, directions: .all)
                XCTAssertEqual(view.cursor(at: corner).image.tiffRepresentation, native.image.tiffRepresentation)
                XCTAssertEqual(view.cursor(at: corner).hotSpot, native.hotSpot)
            }
            XCTAssertTrue(view.cursor(at: center) === NSCursor.arrow)
        }
    }

    func testBackgroundCursorCapabilityIsEnabledWithoutActivatingApplication() async {
        await MainActor.run {
            let application = NSApplication.shared
            let wasActive = application.isActive
            let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            // Read back the WindowServer connection property, rather than
            // confusing our local NSCursor.current with the displayed cursor.
            XCTAssertTrue(BackgroundCursor.enable())
            XCTAssertTrue(BackgroundCursor.isEnabled)
            XCTAssertEqual(application.isActive, wasActive)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, foregroundPID)
        }
    }

    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "io.github.z333d.pinloom.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "soundOff")
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
    }

    private func image(_ name: String) throws -> URL {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 256, bitsPerPixel: 32)!
        bitmap.bitmapData!.initialize(repeating: 200, count: 64 * 32 * 4)
        let url = directory.appendingPathComponent(name).appendingPathExtension("png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    func testReferenceSnapshotSurvivesOriginalDeletionAndRelaunch() async throws {
        let source = try image("original")
        try await MainActor.run {
            let folder = directory.appendingPathComponent("References")
            let library = ReferenceLibrary(folder: folder, defaults: defaults)
            let record = try library.pin(source)
            let expected = try Data(contentsOf: source)
            library.update(record.id, frame: NSRect(x: 100, y: 120, width: 400, height: 300), zoom: 2)
            try FileManager.default.removeItem(at: source)
            let restored = ReferenceLibrary(folder: folder, defaults: defaults)
            XCTAssertEqual(restored.records.count, 1)
            XCTAssertEqual(restored.records[0].zoom, 2)
            XCTAssertEqual(try Data(contentsOf: restored.url(for: restored.records[0])), expected)
        }
    }

    func testUnpinOnlyRemovesSnapshotAndDoesNotDuplicatePins() async throws {
        let source = try image("original")
        try await MainActor.run {
            let library = ReferenceLibrary(folder: directory.appendingPathComponent("References"), defaults: defaults)
            let first = try library.pin(source)
            XCTAssertEqual(try library.pin(source).id, first.id)
            XCTAssertEqual(library.records.count, 1)
            library.remove(first.id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.url(for: first).path))
            XCTAssertTrue(ReferenceLibrary(folder: library.folder, defaults: defaults).records.isEmpty)
        }
    }

    func testInvalidImageCannotCreateReferenceOrMetadata() async throws {
        let source = directory.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: source)
        try await MainActor.run {
            let library = ReferenceLibrary(folder: directory.appendingPathComponent("References"), defaults: defaults)
            XCTAssertThrowsError(try library.pin(source))
            XCTAssertTrue(library.records.isEmpty)
            XCTAssertNil(defaults.data(forKey: "referenceImages"))
        }
    }

    func testTakeDownAndClearKeepOriginalFilesAndDoNotRestoreCards() async throws {
        let source = try image("original")
        await MainActor.run {
            let line = Line(defaults: defaults)
            let id = line.hang(source, quietly: true)!
            line.discard(id)
            XCTAssertEqual(line.liveCount, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertTrue(Line(defaults: defaults).items.isEmpty)
        }
    }

    func testManualImportsKeepAllCardsAndPinnedSnapshotWithoutDeletingSources() async throws {
        let first = try image("first")
        let second = try image("second")
        let third = try image("third")
        try await MainActor.run {
            let line = Line(defaults: defaults)
            let library = ReferenceLibrary(folder: directory.appendingPathComponent("References"), defaults: defaults)
            let record = try library.pin(first)
            line.pinnedPaths = [first.imageIdentityPath]
            _ = line.hang(first, quietly: true)
            _ = line.hang(second, quietly: true)
            _ = line.hang(third, quietly: true)
            XCTAssertEqual(line.items.filter { !$0.falling }.map(\.url), [first, second, third])
            XCTAssertNotNil(makeThumbnail(library.url(for: record)))
            XCTAssertEqual(library.records.count, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        }
    }

    func testClipboardImageIsImportedWithoutChangingPasteboard() async throws {
        let source = try image("clipboard")
        try await MainActor.run {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            let data = try Data(contentsOf: source)
            pasteboard.setData(data, forType: .png)
            let count = pasteboard.changeCount
            let file = try XCTUnwrap(ImageImport.imageFile(from: pasteboard, in: directory.appendingPathComponent("Imports")))
            XCTAssertNotNil(makeThumbnail(file))
            XCTAssertEqual(pasteboard.changeCount, count)
            XCTAssertEqual(pasteboard.data(forType: .png), data)
        }
    }

    @MainActor
    func testMenuBarLeftClickAndAccessibilityToggleWhileRightClickOpensMenu() throws {
        let view = StatusDropView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        var shown = false
        var menuOpens = 0
        view.onClick = { shown.toggle() }
        view.onRightClick = { menuOpens += 1 }
        let left = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let right = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: left)
        XCTAssertTrue(shown)
        XCTAssertEqual(menuOpens, 0)
        view.rightMouseDown(with: right)
        XCTAssertTrue(shown)
        XCTAssertEqual(menuOpens, 1)
        XCTAssertTrue(view.accessibilityPerformPress())
        XCTAssertFalse(shown)
        XCTAssertEqual(menuOpens, 1)
    }

    func testResizingPersistsEveryCardWithoutChangingSourceFilesOrEvictingCards() async throws {
        let sources = try [image("first"), image("second"), image("third")]
        let originalData = try sources.map { try Data(contentsOf: $0) }
        try await MainActor.run {
            let line = Line(defaults: defaults)
            let ids = sources.map { line.hang($0, quietly: true)! }
            for (id, scale) in zip(ids, [0.65, 1.8, 3.0]) { line.resize(id, scale: scale) }
            XCTAssertEqual(line.liveCount, 3)
            XCTAssertEqual(line.items.map(\.scale), [0.65, 1.8, 3.0])
            let restored = Line(defaults: defaults)
            XCTAssertEqual(restored.items.map(\.scale), [0.65, 1.8, 3.0])
            for (source, expected) in zip(sources, originalData) { XCTAssertEqual(try Data(contentsOf: source), expected) }
            let rowWidth = restored.contentWidth + 40
            for index in 0..<2 {
                let left = restored.items[index]
                let right = restored.items[index + 1]
                let leftEdge = Layout.x(index: index, items: restored.items, width: rowWidth)
                    + PeggedView.cardSize(for: left.thumb.size, scale: left.scale).width / 2
                let rightEdge = Layout.x(index: index + 1, items: restored.items, width: rowWidth)
                    - PeggedView.cardSize(for: right.thumb.size, scale: right.scale).width / 2
                XCTAssertLessThan(leftEdge, rightEdge)
            }
        }
    }

    func testExplicitVisibilitySurvivesContentUpdatesAndStartsHiddenAfterRelaunch() async throws {
        let source = try image("quiet-capture")
        await MainActor.run {
            defaults.set(true, forKey: "keepLineVisible") // Older versions must not force startup visibility.
            let line = Line(defaults: defaults)
            XCTAssertFalse(line.revealed)
            let id = line.hang(source, quietly: true)!
            XCTAssertFalse(line.revealed)
            line.setShown(true)
            let noteID = line.addNote()
            line.setNoteText(noteID, text: "Keep working")
            line.resize(id, scale: 1.5)
            line.setNoteText(noteID, text: "Updated")
            XCTAssertTrue(line.revealed)
            line.setShown(false)
            line.setNoteText(noteID, text: "Still saved")
            XCTAssertFalse(line.revealed)
            let restored = Line(defaults: defaults)
            XCTAssertFalse(restored.revealed)
            XCTAssertEqual(restored.items.count, 1)
            XCTAssertEqual(restored.notes.first?.text, "Still saved")
        }
    }

    func testMovingOneImageKeepsNeighboursAndSourceFilesUnchangedAndRestoresAnchors() async throws {
        let sources = try [image("first"), image("second"), image("third")]
        let data = try sources.map { try Data(contentsOf: $0) }
        try await MainActor.run {
            let line = Line(defaults: defaults)
            line.viewportWidth = 1200
            line.availableHeight = 800
            let ids = sources.map { line.hang($0, quietly: true)! }
            let before = line.items.enumerated().map {
                HangingLayout.position(for: $0.element, index: $0.offset, items: line.items, width: 1200, height: 800)
            }
            line.move(ids[1], to: CGPoint(x: 400, y: 300))
            XCTAssertEqual(line.items.map(\.id), ids)
            XCTAssertEqual(line.items[1].hangingPosition, CGPoint(x: 400, y: 300))
            XCTAssertNil(line.items[0].hangingPosition)
            XCTAssertNil(line.items[2].hangingPosition)
            for index in [0, 2] {
                XCTAssertEqual(HangingLayout.position(for: line.items[index], index: index, items: line.items,
                                                      width: 1200, height: 800), before[index])
            }
            line.move(ids[2], to: CGPoint(x: 850, y: 200))
            let restored = Line(defaults: defaults)
            XCTAssertEqual(restored.items[1].hangingPosition, CGPoint(x: 400, y: 300))
            XCTAssertEqual(restored.items[2].hangingPosition, CGPoint(x: 850, y: 200))
            restored.resize(restored.items[1].id, scale: 2)
            XCTAssertEqual(restored.items[1].hangingPosition, CGPoint(x: 400, y: 300))
            for (source, expected) in zip(sources, data) { XCTAssertEqual(try Data(contentsOf: source), expected) }
            restored.resetPosition(restored.items[1].id)
            XCTAssertNil(restored.items[1].hangingPosition)
            XCTAssertEqual(restored.items[2].hangingPosition, CGPoint(x: 850, y: 200))
            XCTAssertEqual(Line(defaults: defaults).items[2].hangingPosition, CGPoint(x: 850, y: 200))
        }
    }

    func testMovedImageIsClampedToCanvasAndRemainsAnchoredWhenNewImagesArrive() async throws {
        let first = try image("first")
        let second = try image("second")
        await MainActor.run {
            let line = Line(defaults: defaults)
            line.viewportWidth = 900
            line.availableHeight = 650
            let id = line.hang(first, quietly: true)!
            line.move(id, to: CGPoint(x: -500, y: 2000))
            let position = line.items[0].hangingPosition!
            let card = PeggedView.cardSize(for: line.items[0].thumb.size)
            XCTAssertGreaterThanOrEqual(position.x - card.width / 2, 0)
            XCTAssertLessThanOrEqual(position.y + card.height + 40, 650)
            _ = line.hang(second, quietly: true)
            XCTAssertEqual(line.items[0].hangingPosition, position)
            line.resetPositions()
            XCTAssertTrue(line.items.allSatisfy { $0.hangingPosition == nil })
            XCTAssertTrue(Line(defaults: defaults).items.allSatisfy { $0.hangingPosition == nil })
        }
    }
}
