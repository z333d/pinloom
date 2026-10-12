import AppKit
import Carbon
import SwiftUI
import XCTest
@testable import Pinloom

@MainActor
final class ShortcutTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var folder: URL!
    override func setUpWithError() throws {
        suite = "PinloomTests.Shortcuts.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: folder)
    }
    private func fakeManager(fail: @escaping (ShortcutKey) -> Bool = { _ in false }) -> GlobalShortcuts {
        GlobalShortcuts(defaults: defaults, register: { key, id in
            fail(key) ? (OSStatus(eventHotKeyExistsErr), nil) : (noErr, EventHotKeyRef(bitPattern: UInt(id)))
        }, unregister: { _ in })
    }
    func testShortcutsPersistChangesDisabledActionsAndRejectDuplicates() {
        let manager = fakeManager()
        XCTAssertEqual(manager.shortcut(for: .hangScreenshot)?.display, "⌃⌥P")
        XCTAssertEqual(manager.shortcut(for: .toggleLine)?.display, "⌃⌥L")
        let custom = ShortcutKey(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertTrue(manager.set(custom, for: .toggleLine))
        XCTAssertFalse(manager.set(custom, for: .hangScreenshot))
        XCTAssertTrue(manager.set(nil, for: .hangScreenshot))
        let restored = fakeManager()
        XCTAssertEqual(restored.shortcut(for: .toggleLine), custom)
        XCTAssertNil(restored.shortcut(for: .hangScreenshot))
        XCTAssertTrue(restored.resetDefaults())
        XCTAssertEqual(fakeManager().shortcut(for: .hangScreenshot), ShortcutAction.hangScreenshot.defaultShortcut)
    }
    func testInvalidCombinationsCannotStealPlainTypingAndFailedRegistrationKeepsOldBinding() {
        var reject = false
        let manager = fakeManager { _ in reject }
        manager.resume()
        let old = manager.shortcut(for: .toggleLine)
        for key in [ShortcutKey(keyCode: 0, modifiers: 0), ShortcutKey(keyCode: 0, modifiers: UInt32(shiftKey)),
                    ShortcutKey(keyCode: 53, modifiers: UInt32(cmdKey)), ShortcutKey(keyCode: 55, modifiers: UInt32(cmdKey))] {
            XCTAssertFalse(manager.set(key, for: .toggleLine))
        }
        reject = true
        XCTAssertFalse(manager.set(ShortcutKey(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey)), for: .toggleLine))
        XCTAssertEqual(manager.shortcut(for: .toggleLine), old)
        var action: ShortcutAction?
        manager.onAction = { action = $0 }
        manager.dispatch(ShortcutAction.toggleLine.identifier)
        XCTAssertEqual(action, .toggleLine)
    }
    func testKeyRepeatSuspensionAndReleaseDoNotToggleRepeatedly() {
        let manager = fakeManager()
        var actions: [ShortcutAction] = []
        manager.onAction = { actions.append($0) }
        manager.handleKey(2, down: true); manager.handleKey(2, down: true)
        XCTAssertEqual(actions, [.toggleLine])
        manager.handleKey(2, down: false); manager.handleKey(2, down: true)
        XCTAssertEqual(actions.count, 2)
        manager.suspend(); manager.dispatch(1)
        XCTAssertEqual(actions.count, 2)
        manager.resume(); manager.handleKey(1, down: true)
        XCTAssertEqual(actions.last, .hangScreenshot)
        manager.dispatch(999)
        XCTAssertEqual(actions.count, 3)
    }
    func testFailedResetRestoresPreviousCustomShortcuts() {
        let custom = ShortcutKey(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey))
        var rejectDefaults = false
        let manager = fakeManager { key in rejectDefaults && key == ShortcutAction.hangScreenshot.defaultShortcut }
        XCTAssertTrue(manager.set(custom, for: .toggleLine))
        rejectDefaults = true
        XCTAssertFalse(manager.resetDefaults())
        XCTAssertEqual(manager.shortcut(for: .toggleLine), custom)
        XCTAssertEqual(fakeManager().shortcut(for: .toggleLine), custom)
    }
    func testClosingSettingsWhileRecordingResumesHotkeysAndCommandKeysAreRecorded() throws {
        _ = NSApplication.shared
        let manager = fakeManager()
        let controller = ShortcutSettingsController(shortcuts: manager, screenshots: RecentScreenshot(defaults: defaults))
        let window = try XCTUnwrap(controller.window)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let buttons = descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? ShortcutRecorder }
        let first = try XCTUnwrap(buttons.first)
        first.beginRecording()
        XCTAssertTrue(manager.suspended)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                                  windowNumber: window.windowNumber, context: nil, characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17))
        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertFalse(manager.suspended)
        XCTAssertEqual(manager.shortcut(for: .hangScreenshot), ShortcutKey(event: event))
        first.beginRecording()
        let second = try XCTUnwrap(buttons.last)
        second.beginRecording()
        XCTAssertTrue(manager.suspended, "Changing the active recorder must keep global keys suspended")
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        XCTAssertFalse(manager.suspended, "Leaving the settings window must restore global keys")
        second.beginRecording()
        controller.close()
        XCTAssertFalse(manager.suspended)
    }
    func testNativeCarbonRegistrationConflictAndEventHandler() throws {
        // Use an isolated, unusual key; never register or invoke the user's shortcuts.
        defaults.set(try JSONEncoder().encode([String: ShortcutKey]()), forKey: "globalShortcuts")
        let manager = GlobalShortcuts(defaults: defaults)
        let rival = GlobalShortcuts(defaults: defaults)
        defer { rival.stop(); manager.stop() }
        manager.start()
        let key = ShortcutKey(keyCode: UInt32(kVK_F19), modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
        XCTAssertTrue(manager.set(key, for: .toggleLine))
        XCTAssertFalse(rival.set(key, for: .toggleLine))
        var actions: [ShortcutAction] = []
        manager.onAction = { actions.append($0) }
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event), noErr)
        let native = try XCTUnwrap(event)
        defer { ReleaseEvent(native) }
        var id = EventHotKeyID(signature: 0x504C4F4D, id: 2)
        XCTAssertEqual(SetEventParameter(native, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id), noErr)
        XCTAssertEqual(SendEventToEventTarget(native, GetApplicationEventTarget()), noErr)
        XCTAssertEqual(actions, [.toggleLine])
    }
    func testRecorderCancelsAndCapturesModifiedKeysWithoutRunningShortcuts() throws {
        let button = ShortcutRecorder()
        var recording: [Bool] = []; var key: ShortcutKey?
        button.onRecording = { recording.append($0) }; button.onShortcut = { key = $0 }
        button.beginRecording()
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        button.keyDown(with: escape)
        XCTAssertFalse(button.recording); XCTAssertNil(key)
        button.beginRecording()
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option], timestamp: 0,
                                                  windowNumber: 0, context: nil, characters: "p", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35))
        button.keyDown(with: event)
        XCTAssertEqual(key, ShortcutAction.hangScreenshot.defaultShortcut)
        XCTAssertEqual(recording, [true, false, true, false])
    }
    func testClipboardShortcutKeepsPasteboardAndDeduplicatesSameCapture() throws {
        let clipboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { clipboard.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 80, height: 40))
        image.lockFocus(); NSColor.orange.setFill(); NSRect(x: 0, y: 0, width: 80, height: 40).fill(); image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        clipboard.setData(tiff, forType: .tiff)
        let count = clipboard.changeCount
        let importer = RecentScreenshot(defaults: defaults)
        let file = try XCTUnwrap(importer.clipboardImage(from: clipboard, destination: folder))
        XCTAssertEqual(try importer.clipboardImage(from: clipboard, destination: folder), file)
        XCTAssertEqual(clipboard.changeCount, count)
        XCTAssertEqual(clipboard.data(forType: .tiff), tiff)
        let line = Line(defaults: defaults)
        XCTAssertNotNil(line.hang(file)); XCTAssertNil(line.hang(file)); XCTAssertEqual(line.items.count, 1)
        // Taking a card down allows the same clipboard image to be hung again.
        try FileManager.default.removeItem(at: file)
        XCTAssertNotEqual(try importer.clipboardImage(from: clipboard, destination: folder), file)
    }
    func testCopiedImageFilesStayOriginalAndTextOrVideosAreNotScreenshots() throws {
        let importer = RecentScreenshot(defaults: defaults)
        let clipboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { clipboard.releaseGlobally() }
        let image = folder.appendingPathComponent("capture.png")
        try Data("fixture".utf8).write(to: image)
        clipboard.writeObjects([image as NSURL])
        XCTAssertEqual(try importer.clipboardImage(from: clipboard), image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
        clipboard.clearContents(); clipboard.setString("https://example.com", forType: .string)
        XCTAssertNil(try importer.clipboardImage(from: clipboard))
        clipboard.clearContents(); clipboard.writeObjects([folder.appendingPathComponent("recording.mov") as NSURL])
        XCTAssertNil(try importer.clipboardImage(from: clipboard))
    }
    func testLatestFolderImageFiltersRegularScreenshotsAndSelectedFoldersAcceptExports() async throws {
        let old = folder.appendingPathComponent("Screenshot old.png")
        let latest = folder.appendingPathComponent("Screenshot latest.png")
        let other = folder.appendingPathComponent("Downloaded.jpg")
        for (index, url) in [old, latest, other].enumerated() {
            try Data("fixture".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index + 1))], ofItemAtPath: url.path)
        }
        let symbolic = folder.appendingPathComponent("Screenshot symlink.png")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: other)
        XCTAssertEqual(try RecentScreenshot.newestImage(in: folder, acceptsAnyImage: false, isScreenshot: { $0.lastPathComponent.hasPrefix("Screenshot") })?.imageIdentityPath, latest.imageIdentityPath)
        let importer = RecentScreenshot(defaults: defaults)
        importer.source = .folder; importer.customFolder = folder
        let newest = try await importer.newestFile()
        XCTAssertEqual(newest?.imageIdentityPath, other.imageIdentityPath)
        let restored = RecentScreenshot(defaults: defaults)
        XCTAssertEqual(restored.source, .folder); XCTAssertEqual(restored.customFolder?.path, folder.path)
        let preferences = ["location": "~/Pictures/Captures", "location-screenshot": "/tmp/Captures"]
        XCTAssertEqual(RecentScreenshot.systemFolder(read: { preferences[$0] }).path, "/tmp/Captures")
    }
    func testScreenshotFocusScrollsIntoOverflowAndClearsOnHide() async throws {
        let line = Line(defaults: defaults)
        line.viewportWidth = 800; line.availableHeight = 600
        for _ in 0..<5 { _ = line.addNote() }
        let image = NSImage(size: NSSize(width: 100, height: 70))
        image.lockFocus(); NSColor.orange.setFill(); NSRect(x: 0, y: 0, width: 100, height: 70).fill(); image.unlockFocus()
        let url = folder.appendingPathComponent("screenshot.tiff")
        try XCTUnwrap(image.tiffRepresentation).write(to: url)
        let id = try XCTUnwrap(line.hang(url))
        // Notes follow images, so put the photo at the far right of the canvas.
        line.move(id, to: CGPoint(x: 1500, y: 80))
        line.setShown(true); line.imageFocusRequest = id
        let host = NSHostingView(rootView: LineView(line: line).transaction { $0.disablesAnimations = true })
        host.sizingOptions = []
        let panel = LinePanel(content: host)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 0, y: 0, width: 800, height: 500), display: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> GrabView? { (view as? GrabView) ?? view.subviews.compactMap(find).first }
        let grab = try XCTUnwrap(find(host))
        XCTAssertTrue(host.bounds.intersects(grab.convert(grab.bounds, to: host)))
        line.setShown(false)
        XCTAssertNil(line.imageFocusRequest)
    }
}
