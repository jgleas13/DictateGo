import AppKit
import Carbon
import Foundation

struct Hotkey: Codable, Equatable {
    var keyCode: UInt16?
    var modifiers: UInt

    static let `default` = Hotkey(keyCode: nil, modifiers: NSEvent.ModifierFlags.option.rawValue)
    static let legacyDefaultOptionSpace = Hotkey(
        keyCode: UInt16(kVK_Space),
        modifiers: NSEvent.ModifierFlags.option.rawValue
    )

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        let flags = Hotkey.normalizedFlags(modifierFlags)
        var parts: [String] = []
        if flags.contains(.command) { parts.append("⌘") }
        if flags.contains(.option) { parts.append("⌥ Option") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.control) { parts.append("⌃") }
        if let keyCode {
            parts.append(Hotkey.keyName(for: keyCode))
        }
        if parts.isEmpty {
            return "Unset"
        }
        return parts.joined(separator: " + ")
    }

    static func from(event: NSEvent) -> Hotkey {
        let flags = normalizedFlags(event.modifierFlags)
        return Hotkey(keyCode: event.keyCode, modifiers: flags.rawValue)
    }

    static func normalizedFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .shift, .control])
    }

    static func keyName(for keyCode: UInt16) -> String {
        if let name = keyCodeNames[keyCode] {
            return name
        }
        return "Key \(keyCode)"
    }
}

private func vk(_ value: Int) -> UInt16 {
    UInt16(value)
}

private let keyCodeNames: [UInt16: String] = [
    vk(kVK_ANSI_A): "A",
    vk(kVK_ANSI_B): "B",
    vk(kVK_ANSI_C): "C",
    vk(kVK_ANSI_D): "D",
    vk(kVK_ANSI_E): "E",
    vk(kVK_ANSI_F): "F",
    vk(kVK_ANSI_G): "G",
    vk(kVK_ANSI_H): "H",
    vk(kVK_ANSI_I): "I",
    vk(kVK_ANSI_J): "J",
    vk(kVK_ANSI_K): "K",
    vk(kVK_ANSI_L): "L",
    vk(kVK_ANSI_M): "M",
    vk(kVK_ANSI_N): "N",
    vk(kVK_ANSI_O): "O",
    vk(kVK_ANSI_P): "P",
    vk(kVK_ANSI_Q): "Q",
    vk(kVK_ANSI_R): "R",
    vk(kVK_ANSI_S): "S",
    vk(kVK_ANSI_T): "T",
    vk(kVK_ANSI_U): "U",
    vk(kVK_ANSI_V): "V",
    vk(kVK_ANSI_W): "W",
    vk(kVK_ANSI_X): "X",
    vk(kVK_ANSI_Y): "Y",
    vk(kVK_ANSI_Z): "Z",
    vk(kVK_ANSI_0): "0",
    vk(kVK_ANSI_1): "1",
    vk(kVK_ANSI_2): "2",
    vk(kVK_ANSI_3): "3",
    vk(kVK_ANSI_4): "4",
    vk(kVK_ANSI_5): "5",
    vk(kVK_ANSI_6): "6",
    vk(kVK_ANSI_7): "7",
    vk(kVK_ANSI_8): "8",
    vk(kVK_ANSI_9): "9",
    vk(kVK_Space): "Space",
    vk(kVK_Return): "Return",
    vk(kVK_Tab): "Tab",
    vk(kVK_Escape): "Esc",
    vk(kVK_Delete): "Delete",
    vk(kVK_ForwardDelete): "Forward Delete"
]
