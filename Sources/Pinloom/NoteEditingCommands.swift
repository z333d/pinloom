import AppKit

/// Standard editing commands routed to the nonactivating panel's editor,
/// including the shared NSTextView field editor used by to-do text fields.
enum NoteEditingCommands {
    static func perform(_ event: NSEvent, on responder: NSResponder?) -> Bool {
        guard let text = responder as? NSTextView else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags == .command || flags == [.command, .shift] else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags.contains(.shift) {
            guard key == "z" else { return false }
            text.undoManager?.redo()
            return true
        }
        switch key {
        case "c": text.copy(nil)
        case "x": text.cut(nil)
        case "v": text.paste(nil)
        case "a": text.selectAll(nil)
        case "z": text.undoManager?.undo()
        default: return false
        }
        return true
    }

    static func menu() -> NSMenu {
        let menu = NSMenu(title: L("Edit"))
        func add(_ title: String, _ action: Selector, _ key: String, shift: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : .command
            menu.addItem(item) // A nil target follows the active responder chain.
        }
        add(L("Undo"), Selector(("undo:")), "z")
        add(L("Redo"), Selector(("redo:")), "z", shift: true)
        menu.addItem(.separator())
        add(L("Cut"), #selector(NSText.cut(_:)), "x")
        add(L("Copy"), #selector(NSText.copy(_:)), "c")
        add(L("Paste"), #selector(NSText.paste(_:)), "v")
        add(L("Select All"), #selector(NSText.selectAll(_:)), "a")
        return menu
    }
}
