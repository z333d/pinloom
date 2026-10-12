import AppKit
import Carbon

enum ShortcutAction: String, CaseIterable {
    case hangScreenshot, toggleLine
    var identifier: UInt32 { self == .hangScreenshot ? 1 : 2 }
    var title: String { self == .hangScreenshot ? L("Hang recent screenshot") : L("Show or hide line") }
    var defaultShortcut: ShortcutKey {
        ShortcutKey(keyCode: UInt32(self == .hangScreenshot ? kVK_ANSI_P : kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey))
    }
}

struct ShortcutKey: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    var valid: Bool {
        keyCode < 128 && keyCode != UInt32(kVK_Escape)
            && modifiers & ~Self.allowedModifiers == 0
            && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
            && ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var bits: UInt32 = 0
        for (flag, value) in [(NSEvent.ModifierFlags.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey)] {
            if event.modifierFlags.contains(flag) { bits |= UInt32(value) }
        }
        modifiers = bits
    }
    var display: String {
        var value = ""
        for (bit, glyph) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(bit) != 0 { value += glyph }
        }
        let special: [UInt32: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                       122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
                                       101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
                                       106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        if let name = special[keyCode] { return value + name }
        // Resolve letters using the active keyboard layout, not US key positions.
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var state: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            if UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                              OptionBits(kUCKeyTranslateNoDeadKeysMask), &state, characters.count, &length, &characters) == noErr, length > 0 {
                return value + String(utf16CodeUnits: characters, count: length).uppercased()
            }
        }
        return value + "Key \(keyCode)"
    }
    func apply(to item: NSMenuItem) {
        let special: [UInt32: String] = [36: "\r", 48: "\t", 49: " ", 51: "\u{8}",
                                        123: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                                        124: String(UnicodeScalar(NSRightArrowFunctionKey)!),
                                        125: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                                        126: String(UnicodeScalar(NSUpArrowFunctionKey)!)]
        let name = display.drop(while: { "⌃⌥⇧⌘".contains($0) })
        item.keyEquivalent = special[keyCode] ?? (name.count == 1 ? String(name).lowercased() : "")
        var flags: NSEvent.ModifierFlags = []
        for (bit, flag) in [(cmdKey, NSEvent.ModifierFlags.command), (controlKey, .control), (optionKey, .option), (shiftKey, .shift)] {
            if modifiers & UInt32(bit) != 0 { flags.insert(flag) }
        }
        item.keyEquivalentModifierMask = flags
    }
}

@MainActor
final class GlobalShortcuts {
    private static let signature: OSType = 0x504C4F4D // PLOM
    private let defaults: UserDefaults
    private var keys: [ShortcutAction: ShortcutKey] = [:]
    private var references: [ShortcutAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private(set) var suspended = false
    private var pressed = Set<UInt32>()
    private(set) var failures: Set<ShortcutAction> = []
    var onAction: (ShortcutAction) -> Void = { _ in }
    // An injected registrar lets conflict and rollback tests avoid global keys.
    private let register: @MainActor (ShortcutKey, UInt32) -> (OSStatus, EventHotKeyRef?)
    private let unregister: @MainActor (EventHotKeyRef) -> Void

    init(defaults: UserDefaults = .standard,
         register: @escaping @MainActor (ShortcutKey, UInt32) -> (OSStatus, EventHotKeyRef?) = GlobalShortcuts.registerKey,
         unregister: @escaping @MainActor (EventHotKeyRef) -> Void = { UnregisterEventHotKey($0) }) {
        self.defaults = defaults; self.register = register; self.unregister = unregister
        if let data = defaults.data(forKey: "globalShortcuts"), let stored = try? JSONDecoder().decode([String: ShortcutKey].self, from: data) {
            for action in ShortcutAction.allCases {
                if let key = stored[action.rawValue], key.valid, !keys.values.contains(key) { keys[action] = key }
            }
        } else { for action in ShortcutAction.allCases { keys[action] = action.defaultShortcut } }
    }

    func shortcut(for action: ShortcutAction) -> ShortcutKey? { keys[action] }
    func start() {
        guard handler == nil else { return }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let owner = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == GlobalShortcuts.signature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated { manager.handleKey(id.id, down: down) }
            return noErr
        }, 2, &types, owner, &handler)
        guard status == noErr else { failures = Set(keys.keys); return }
        resume()
    }
    func dispatch(_ identifier: UInt32) {
        guard !suspended, let action = ShortcutAction.allCases.first(where: { $0.identifier == identifier }),
              keys[action] != nil, !failures.contains(action) else { return }
        onAction(action)
    }
    func handleKey(_ identifier: UInt32, down: Bool) {
        if !down { pressed.remove(identifier); return }
        guard pressed.insert(identifier).inserted else { return }
        dispatch(identifier)
    }
    func suspend() {
        suspended = true
        pressed.removeAll()
        for ref in references.values { unregister(ref) }
        references.removeAll()
    }
    func resume() {
        suspended = false; failures.removeAll()
        for (action, key) in keys where references[action] == nil {
            let (status, ref) = register(key, action.identifier)
            if status == noErr, let ref { references[action] = ref } else { failures.insert(action) }
        }
    }
    @discardableResult
    func set(_ key: ShortcutKey?, for action: ShortcutAction) -> Bool {
        if let key, !key.valid || keys.contains(where: { $0.key != action && $0.value == key }) { return false }
        if keys[action] == key, !failures.contains(action) { return true }
        var newReference: EventHotKeyRef?
        if let key, !suspended {
            let (status, ref) = register(key, action.identifier)
            guard status == noErr, let ref else { return false }
            newReference = ref
        }
        if let ref = references.removeValue(forKey: action) { unregister(ref) }
        keys[action] = key
        if let newReference { references[action] = newReference }
        failures.remove(action)
        save()
        return true
    }
    func stop() {
        suspend()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
    func resetDefaults() -> Bool {
        let old = keys
        for action in ShortcutAction.allCases { _ = set(nil, for: action) }
        for action in ShortcutAction.allCases {
            guard set(action.defaultShortcut, for: action) else {
                for item in ShortcutAction.allCases { _ = set(nil, for: item) }
                for (item, key) in old { _ = set(key, for: item) }
                return false
            }
        }
        return true
    }
    private func save() {
        let values = Dictionary(uniqueKeysWithValues: keys.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(values), forKey: "globalShortcuts")
    }
    private static func registerKey(_ key: ShortcutKey, _ identifier: UInt32) -> (OSStatus, EventHotKeyRef?) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: identifier)
        let status = RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        return (status, ref)
    }
}
