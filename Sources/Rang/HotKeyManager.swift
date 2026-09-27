import AppKit
import Carbon

struct Shortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let `default` = Shortcut(keyCode: 8, modifiers: UInt32(controlKey | optionKey), keyLabel: "C")

    var displayText: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0,
              event.keyCode != 53 else { return nil }
        let label = event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !label.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
    }
}

final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var shortcut: Shortcut = .default
    private(set) var registrationError: OSStatus?
    var onPress: (() -> Void)?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onPress?()
            return noErr
        }, 1, &eventType, pointer, &handler)

        let defaults = UserDefaults.standard
        if let label = defaults.string(forKey: "shortcutLabel") {
            let saved = Shortcut(keyCode: UInt32(defaults.integer(forKey: "shortcutKeyCode")),
                                 modifiers: UInt32(defaults.integer(forKey: "shortcutModifiers")),
                                 keyLabel: label)
            if register(saved) == noErr { return }
        }
        _ = register(.default)
    }

    @discardableResult
    func register(_ newShortcut: Shortcut) -> OSStatus {
        if hotKey != nil && newShortcut.keyCode == shortcut.keyCode && newShortcut.modifiers == shortcut.modifiers {
            shortcut = newShortcut
            UserDefaults.standard.set(newShortcut.keyLabel, forKey: "shortcutLabel")
            return noErr
        }
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x52616E67, id: 1)
        let status = RegisterEventHotKey(newShortcut.keyCode, newShortcut.modifiers, identifier,
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        guard status == noErr else {
            registrationError = status
            return status
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = reference
        shortcut = newShortcut
        registrationError = nil
        let defaults = UserDefaults.standard
        defaults.set(Int(newShortcut.keyCode), forKey: "shortcutKeyCode")
        defaults.set(Int(newShortcut.modifiers), forKey: "shortcutModifiers")
        defaults.set(newShortcut.keyLabel, forKey: "shortcutLabel")
        return noErr
    }

    func suspend() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    func resume() {
        guard hotKey == nil else { return }
        _ = register(shortcut)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
