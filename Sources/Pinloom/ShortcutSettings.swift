import AppKit

private final class ShortcutSettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let recorder = firstResponder as? ShortcutRecorder, recorder.recording {
            recorder.keyDown(with: event); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class ShortcutRecorder: NSButton {
    private(set) var recording = false
    var onRecording: (Bool) -> Void = { _ in }
    var onShortcut: (ShortcutKey) -> Void = { _ in }
    var onCancel: () -> Void = {}
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded; target = self; action = #selector(beginRecording)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func beginRecording() {
        window?.makeFirstResponder(self)
        recording = true
        title = L("Press shortcut…")
        onRecording(true)
    }
    func cancelRecording() {
        guard recording else { return }
        recording = false; onRecording(false); onCancel()
    }
    override func resignFirstResponder() -> Bool { cancelRecording(); return true }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { cancelRecording(); return }
        let shortcut = ShortcutKey(event: event)
        guard shortcut.valid else { NSSound.beep(); return }
        recording = false; onRecording(false); onShortcut(shortcut)
    }
}

@MainActor
final class ShortcutSettingsController: NSWindowController, NSWindowDelegate {
    private let shortcuts: GlobalShortcuts
    private let screenshots: RecentScreenshot
    private var recorders: [ShortcutAction: ShortcutRecorder] = [:]
    private let message = NSTextField(wrappingLabelWithString: "")
    private let source = NSPopUpButton()
    private let folderPath = NSTextField(labelWithString: "")
    private let choose = NSButton()
    private let system = NSButton()

    init(shortcuts: GlobalShortcuts, screenshots: RecentScreenshot) {
        self.shortcuts = shortcuts; self.screenshots = screenshots
        let window = ShortcutSettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 355),
                                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Shortcuts…"); window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self; window.center()
        let body = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 355))
        window.contentView = body
        func label(_ title: String, _ rect: NSRect, font: NSFont = .systemFont(ofSize: 13)) {
            let field = NSTextField(wrappingLabelWithString: title); field.frame = rect; field.font = font; body.addSubview(field)
        }
        label(L("Global shortcuts"), NSRect(x: 24, y: 303, width: 490, height: 24), font: .systemFont(ofSize: 17, weight: .semibold))
        label(L("Click a shortcut, then press Control, Option or Command with a key. Escape cancels."), NSRect(x: 24, y: 259, width: 490, height: 38), font: .systemFont(ofSize: 12))
        for (index, action) in ShortcutAction.allCases.enumerated() {
            let y = 209 - CGFloat(index) * 42
            label(action.title, NSRect(x: 24, y: y + 4, width: 258, height: 20))
            let recorder = ShortcutRecorder(frame: NSRect(x: 282, y: y, width: 170, height: 30))
            recorder.setAccessibilityLabel(action.title)
            recorder.onRecording = { [weak shortcuts] active in if active { shortcuts?.suspend() } else { shortcuts?.resume() } }
            recorder.onCancel = { [weak self] in self?.refresh() }
            recorder.onShortcut = { [weak self] key in
                guard let self else { return }
                let accepted = self.shortcuts.set(key, for: action)
                self.refresh()
                if !accepted { self.message.stringValue = L("Shortcut unavailable. Choose another combination.") }
            }
            body.addSubview(recorder); recorders[action] = recorder
            let clear = NSButton(title: "×", target: self, action: #selector(clearShortcut(_:)))
            clear.tag = index; clear.frame = NSRect(x: 460, y: y, width: 48, height: 30); clear.bezelStyle = .rounded
            clear.setAccessibilityLabel(L("Disable shortcut") + ": " + action.title)
            body.addSubview(clear)
        }
        source.frame = NSRect(x: 212, y: 115, width: 300, height: 30)
        source.addItems(withTitles: ScreenshotSource.allCases.map(\.title)); source.target = self; source.action = #selector(changeSource)
        source.setAccessibilityLabel(L("Screenshot source")); body.addSubview(source)
        label(L("Screenshot source"), NSRect(x: 24, y: 120, width: 180, height: 20))
        folderPath.frame = NSRect(x: 24, y: 85, width: 488, height: 20)
        folderPath.font = .systemFont(ofSize: 11); folderPath.textColor = .secondaryLabelColor
        folderPath.lineBreakMode = .byTruncatingMiddle; body.addSubview(folderPath)
        choose.title = L("Choose folder…"); choose.target = self; choose.action = #selector(chooseFolder)
        choose.bezelStyle = .rounded; choose.frame = NSRect(x: 24, y: 46, width: 140, height: 30); body.addSubview(choose)
        system.title = L("Use system folder"); system.target = self; system.action = #selector(useSystemFolder)
        system.bezelStyle = .rounded; system.frame = NSRect(x: 171, y: 46, width: 155, height: 30); body.addSubview(system)
        let reset = NSButton(title: L("Reset shortcuts"), target: self, action: #selector(resetShortcuts))
        reset.bezelStyle = .rounded; reset.frame = NSRect(x: 350, y: 46, width: 162, height: 30); body.addSubview(reset)
        message.frame = NSRect(x: 24, y: 7, width: 488, height: 32); message.font = .systemFont(ofSize: 11)
        message.textColor = .secondaryLabelColor; body.addSubview(message)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    func open() { refresh(); NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) { recorders.values.forEach { $0.cancelRecording() } }
    func windowDidResignKey(_ notification: Notification) { recorders.values.forEach { $0.cancelRecording() } }
    private func refresh() {
        for (action, recorder) in recorders where !recorder.recording {
            recorder.title = shortcuts.shortcut(for: action)?.display ?? L("Disabled")
        }
        source.selectItem(at: ScreenshotSource.allCases.firstIndex(of: screenshots.source) ?? 0)
        let folderMode = screenshots.source == .folder
        folderPath.stringValue = folderMode ? screenshots.folder.path : L("Copy a screenshot, then press the shortcut to hang it.")
        folderPath.toolTip = folderPath.stringValue
        choose.isEnabled = folderMode; system.isEnabled = folderMode && screenshots.customFolder != nil
        message.stringValue = shortcuts.failures.isEmpty ? "" : L("Shortcut unavailable. Choose another combination.")
    }
    @objc private func clearShortcut(_ sender: NSButton) {
        window?.makeFirstResponder(nil)
        _ = shortcuts.set(nil, for: ShortcutAction.allCases[sender.tag]); refresh()
    }
    @objc private func resetShortcuts() {
        window?.makeFirstResponder(nil)
        let accepted = shortcuts.resetDefaults()
        refresh()
        if !accepted { message.stringValue = L("Shortcut unavailable. Choose another combination.") }
    }
    @objc private func changeSource() {
        screenshots.source = ScreenshotSource.allCases[source.indexOfSelectedItem]; refresh()
    }
    @objc private func chooseFolder() {
        let chooser = NSOpenPanel(); chooser.canChooseFiles = false; chooser.canChooseDirectories = true
        chooser.allowsMultipleSelection = false; chooser.directoryURL = screenshots.folder
        guard chooser.runModal() == .OK, let url = chooser.url else { return }
        screenshots.customFolder = url; refresh()
    }
    @objc private func useSystemFolder() { screenshots.customFolder = nil; refresh() }
}
