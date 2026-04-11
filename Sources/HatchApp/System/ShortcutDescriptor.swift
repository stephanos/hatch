import AppKit
import Carbon

struct ShortcutDescriptor: Codable, Equatable {
  let keyCode: UInt32
  let modifierFlagsRawValue: UInt

  var modifierFlags: NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
      .intersection([.command, .option, .control, .shift])
  }

  var carbonModifierFlags: UInt32 {
    var flags: UInt32 = 0
    if modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
    if modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
    if modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
    if modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
    return flags
  }

  var displayString: String {
    let modifiers = [
      modifierFlags.contains(.control) ? "^" : nil,
      modifierFlags.contains(.option) ? "⌥" : nil,
      modifierFlags.contains(.shift) ? "⇧" : nil,
      modifierFlags.contains(.command) ? "⌘" : nil,
    ]
    .compactMap { $0 }
    .joined()
    return modifiers + Self.keyLabel(for: keyCode)
  }

  static func from(event: NSEvent) -> ShortcutDescriptor? {
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    guard !flags.isEmpty else {
      return nil
    }
    return ShortcutDescriptor(
      keyCode: UInt32(event.keyCode),
      modifierFlagsRawValue: flags.rawValue
    )
  }

  private static func keyLabel(for keyCode: UInt32) -> String {
    if let special = specialKeys[keyCode] {
      return special
    }
    if let scalar = printableKeyScalars[keyCode] {
      return String(scalar).uppercased()
    }
    return "Key \(keyCode)"
  }

  private static let printableKeyScalars: [UInt32: Character] = [
    0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
    8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
    16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
    23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
    30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
    38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
    45: "n", 46: "m", 47: ".", 50: "`",
  ]

  private static let specialKeys: [UInt32: String] = [
    36: "↩",
    48: "⇥",
    49: "Space",
    51: "⌫",
    53: "⎋",
    115: "↖",
    116: "⇞",
    117: "⌦",
    119: "↘",
    121: "⇟",
    123: "←",
    124: "→",
    125: "↓",
    126: "↑",
  ]
}
