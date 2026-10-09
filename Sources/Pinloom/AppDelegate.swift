import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let line: Line
    private let references: ReferenceImages
    private var panel: LinePanel!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var cancellables = Set<AnyCancellable>()
    private var mouseTimer: Timer?

    override init() {
        do { try LegacyDataMigration.run() }
        catch { log.warning("Legacy data migration will retry on next launch: \(error.localizedDescription, privacy: .public)") }
        line = Line()
        references = ReferenceImages()
        super.init()
    }

    init(line: Line, references: ReferenceImages) {
        self.line = line
        self.references = references
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !BackgroundCursor.enable() {
            log.warning("Background cursor support unavailable; the visible resize handle remains usable")
        }
        let host = DropHostingView(rootView: LineView(line: line))
        host.sizingOptions = []
        host.registerForDraggedTypes([.fileURL, .png, .tiff])
        host.onDrop = { [weak self] pasteboard in self?.importImages(pasteboard) ?? false }
        panel = LinePanel(content: host)
        placeLine()

        // Upgrade cleanup only: restore settings left by the removed inbox
        // mode without ever taking control of screenshots again.
        if let legacy = UserDefaults(suiteName: "app.tendedero.Tendedero") {
            LegacyScreenshotSettings.restoreIfNeeded(defaults: legacy)
        }

        references.onError = { [weak self] error in self?.showError(L("Could not pin image"), error.localizedDescription) }
        line.onPin = { [weak self] url in self?.references.pin(url) }
        line.onPreview = { [weak self] url in self?.references.showPreview(url) }
        line.onLayoutChange = { [weak self] in
            guard let self else { return }
            self.placeLine(on: self.panel.screen)
        }
        line.onHideLine = { [weak self] in self?.line.setShown(false) }
        line.onPasteImage = { [weak self] in _ = self?.importImages(.general) }
        line.onChooseImages = { [weak self] in self?.chooseImages() }
        line.onImportImages = { [weak self] pasteboard in self?.importImages(pasteboard) ?? false }
        line.onCreateNote = { [weak self] in self?.createNote() }
        line.onFinishNoteEditing = { [weak self] in self?.panel.resignKey() }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.line.editingNoteID = nil }
        }
        references.library.$records.sink { [weak self] records in
            self?.line.pinnedPaths = Set(records.map(\.sourcePath))
        }.store(in: &cancellables)
        references.restore()

        line.$revealed.dropFirst().sink { [weak self] shown in
            self?.visibilityChanged(shown)
        }.store(in: &cancellables)
        setUpStatusItem()

        Markup.shared.onSaved = { [weak self] url in self?.line.reloadThumbnail(for: url) }
        line.onFall = { [weak self] item in self?.fall(item) }

        line.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.itemsChanged() }
            .store(in: &cancellables)
        line.$notes.receive(on: RunLoop.main).sink { [weak self] _ in self?.itemsChanged() }.store(in: &cancellables)

        // Keep an explicitly opened line above applications after a Space
        // switch. These notifications never open a hidden line.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.bringVisibleLineForward()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.bringVisibleLineForward() }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.placeLine()
                self?.references.reposition()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopMouseTracking()
        references.saveFrames()
    }

    // MARK: Showing and hiding

    private func itemsChanged() {
        // Collecting or removing content only changes the layout. Visibility
        // belongs to the user's explicit show/hide actions.
        placeLine(on: panel.screen)
    }

    // MARK: Taking an image down

    /// A discarded card falls over the whole screen, from where it hangs.
    private func fall(_ item: Pegged) {
        guard line.revealed, let screen = panel.screen,
              let card = cardFrame(for: item.id),
              let image = item.thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        FallingCard.fall(image: image, card: card, tilt: CGFloat(item.tilt), on: screen)
    }

    /// Where a card will hang, in screen coordinates, using the same layout
    /// as the line view.
    private func cardFrame(for id: UUID) -> CGRect? {
        guard let rect = line.hitRects[id], rect.width > 0, rect.height > 0,
              rect.intersects(CGRect(origin: .zero, size: panel.frame.size)) else { return nil }
        return CGRect(x: panel.frame.minX + rect.minX, y: panel.frame.maxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }

    private func visibilityChanged(_ shown: Bool) {
        if shown {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            startMouseTracking()
        } else {
            panel.resignKey()
            stopMouseTracking()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, !self.line.revealed else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func bringVisibleLineForward() {
        if line.revealed { panel.orderFrontRegardless() }
    }

    @objc private func toggle() {
        if line.revealed { line.setShown(false) }
        else { showLineOnPurpose() }
    }

    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        panel.ignoresMouseEvents = true
    }

    private func tick() {
        guard line.revealed else { return }
        updateMousePassThrough(NSEvent.mouseLocation)
    }

    /// The panel spans the whole width of the screen, so it only accepts the
    /// mouse while the cursor is over a photo. Everywhere else, clicks go to
    /// whatever is underneath.
    private func updateMousePassThrough(_ mouse: NSPoint) {
        guard !GrabView.isDragging, line.resizingID == nil, line.movingItemID == nil else { return }
        let local = panel.convertPoint(fromScreen: mouse)
        let target = panel.interactiveView(atWindowPoint: local)
        let overPhoto = target != nil
        if panel.ignoresMouseEvents == overPhoto {
            panel.ignoresMouseEvents = !overPhoto
        }
        // Enabling hit testing under an already stationary pointer may not
        // generate a fresh mouse-entered event. Keep the inactive panel's
        // resize cursor in sync with the same polling used for pass-through.
        if let grab = target as? GrabView {
            grab.updatePointer(at: grab.convert(local, from: nil))
        } else if target is NoteResizeView {
            GrabView.resizeCursor.set()
        } else if target is LineImportView || target is LineDismissView {
            NSCursor.arrow.set()
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "pin.circle", accessibilityDescription: "Pinloom")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        let mainMenu = NSMenu()
        let applicationMenu = NSMenuItem(title: "Pinloom", action: nil, keyEquivalent: "")
        let commands = NSMenu()
        commands.delegate = self
        applicationMenu.submenu = commands
        mainMenu.addItem(applicationMenu)
        let edit = NSMenuItem(title: L("Edit"), action: nil, keyEquivalent: "")
        edit.submenu = NoteEditingCommands.menu()
        mainMenu.addItem(edit)
        NSApp.mainMenu = mainMenu
        if let button = statusItem.button {
            let drop = StatusDropView(frame: button.bounds)
            drop.autoresizingMask = [.width, .height]
            drop.onDrop = { [weak self] pasteboard in self?.importImages(pasteboard) ?? false }
            drop.onClick = { [weak self] in self?.toggle() }
            drop.onRightClick = { [weak self, weak drop] in
                guard let self, let drop, let menu = self.statusMenu else { return }
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: drop.bounds.height), in: drop)
            }
            button.addSubview(drop)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(ClosureMenuItem(line.revealed ? L("Hide line") : L("Show line")) { [weak self] in self?.toggle() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Paste image")) { [weak self] in _ = self?.importImages(.general) })
        menu.addItem(ClosureMenuItem(L("Add images…")) { [weak self] in self?.chooseImages() })
        menu.addItem(ClosureMenuItem(L("New note")) { [weak self] in self?.createNote() })
        if line.lastRemovedNote != nil {
            menu.addItem(ClosureMenuItem(L("Restore last note")) { [weak self] in
                self?.line.restoreLastNote(); self?.showLineOnPurpose()
            })
        }
        if !references.library.records.isEmpty {
            menu.addItem(ClosureMenuItem(references.hidden ? L("Show reference images") : L("Hide reference images")) { [weak self] in
                self?.references.toggleHidden()
            })
        }
        menu.addItem(.separator())
        if line.totalCount > 0 {
            let arrange = NSMenuItem(title: L("Arrange"), action: nil, keyEquivalent: "")
            let actions = NSMenu()
            let reset = ClosureMenuItem(L("Reset all positions")) { [weak self] in self?.line.resetPositions() }
            reset.isEnabled = line.items.contains { $0.hangingPosition != nil } || line.notes.contains { $0.x != nil || $0.y != nil }
            actions.addItem(reset)
            let clear = ClosureMenuItem(L("Take images down")) { [weak self] in self?.line.clear() }
            clear.isEnabled = line.liveCount > 0
            actions.addItem(clear)
            actions.autoenablesItems = false
            arrange.submenu = actions
            menu.addItem(arrange)
        }
        let options = NSMenuItem(title: L("Options"), action: nil, keyEquivalent: "")
        let settings = NSMenu()
        let sound = ClosureMenuItem(L("Sounds")) { [weak self] in self?.line.soundOn.toggle() }
        sound.state = line.soundOn ? .on : .off
        settings.addItem(sound)
        let login = ClosureMenuItem(L("Open at login")) { AppDelegate.toggleLaunchAtLogin() }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        settings.addItem(login)
        options.submenu = settings
        menu.addItem(options)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Quit Pinloom"), key: "q") { NSApp.terminate(nil) })
    }

    // MARK: Sources and explicit actions

    private func placeLine(on screen: NSScreen? = nil) {
        guard let screen = screen ?? LinePanel.screenUnderPointer() else { return }
        let available = LinePanel.usableFrame(of: screen)
        line.availableHeight = available.height
        line.viewportWidth = available.width
        panel.placeOnScreen(screen, height: line.panelHeight)
    }

    private func chooseImages() {
        let chooser = NSOpenPanel()
        chooser.allowedContentTypes = [.image]
        chooser.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard chooser.runModal() == .OK else { return }
        var accepted = false
        for url in chooser.urls { if line.hang(url) != nil { accepted = true } }
        if accepted { showLineOnPurpose() }
    }

    @discardableResult
    private func importImages(_ pasteboard: NSPasteboard) -> Bool {
        var accepted = false
        let urls = ImageImport.urls(from: pasteboard)
        for url in urls {
            if line.items.contains(where: { $0.url.imageIdentityPath == url.imageIdentityPath && !$0.falling }) {
                accepted = true
            } else if line.hang(url) != nil { accepted = true }
        }
        if !accepted && urls.isEmpty {
            do {
                if let url = try ImageImport.imageFile(from: pasteboard) { accepted = line.hang(url) != nil }
            } catch { showError(L("Could not import image"), error.localizedDescription); return false }
        }
        if accepted { showLineOnPurpose() }
        else { showError(L("No image found"), L("Copy an image or an image file, then try again.")) }
        return accepted
    }

    private func showLineOnPurpose() {
        line.prune()
        placeLine(on: line.revealed ? panel.screen : nil)
        if line.revealed { panel.orderFrontRegardless() }
        else { line.setShown(true) }
    }

    private func createNote() {
        let id = line.addNote()
        showLineOnPurpose()
        line.editingNoteID = id
        line.noteFocusRequest = id
    }

    private func showError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Could not change the login setting")
            alert.informativeText = L("Move Pinloom to the Applications folder and try again.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
