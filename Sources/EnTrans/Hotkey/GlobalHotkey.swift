import AppKit
import Carbon
import Foundation

struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    static let defaultSpec = HotkeySpec(
        keyCode: 0x0E,
        carbonModifiers: UInt32(controlKey | optionKey),
        keyLabel: "E"
    )

    var display: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyLabel.isEmpty ? "?" : keyLabel)
        return parts.joined()
    }

    static func from(event: NSEvent) -> HotkeySpec? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else { return nil }
        let raw = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        let label = raw.count == 1 ? raw.uppercased() : raw
        return HotkeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers, keyLabel: label)
    }
}

@MainActor
enum HotkeyBridge {
    static var onFire: (() -> Void)?
}

/// Carbon hotkeys are delivered through a C function pointer, so the callback stays a free function.
private func entransHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ theEvent: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    Task { @MainActor in
        HotkeyBridge.onFire?()
    }
    return noErr
}

@MainActor
final class GlobalHotkey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var installed = false

    func register(_ spec: HotkeySpec) -> Bool {
        unregister()
        guard installHandlerIfNeeded() else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.carbonModifiers,
            EventHotKeyID(signature: fourCharCode("ENTR"), id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKey = ref
        return true
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installHandlerIfNeeded() -> Bool {
        if installed { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            entransHotKeyHandler,
            1,
            &eventType,
            nil,
            &handler
        )
        installed = status == noErr
        return installed
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for byte in string.utf8.prefix(4) {
        result = (result << 8) + OSType(byte)
    }
    return result
}
