import AppKit
import SwiftUI

@MainActor
final class ShortcutStore: ObservableObject {
  static let shared = ShortcutStore()
  static let defaultOpenHatchShortcut = ShortcutDescriptor(
    keyCode: 4,
    modifierFlagsRawValue:
      NSEvent.ModifierFlags.control.rawValue
      | NSEvent.ModifierFlags.option.rawValue
      | NSEvent.ModifierFlags.command.rawValue
  )

  @Published private(set) var openHatchShortcut: ShortcutDescriptor?
  @Published private(set) var isOpenHatchShortcutDisabled: Bool

  private let defaults = UserDefaults.standard
  private let key = "openHatchShortcut"
  private let disabledKey = "openHatchShortcutDisabled"

  private init() {
    isOpenHatchShortcutDisabled = defaults.bool(forKey: disabledKey)
    openHatchShortcut = loadShortcut()
  }

  var effectiveOpenHatchShortcut: ShortcutDescriptor? {
    guard !isOpenHatchShortcutDisabled else {
      return nil
    }
    return openHatchShortcut ?? Self.defaultOpenHatchShortcut
  }

  var isUsingDefaultOpenHatchShortcut: Bool {
    !isOpenHatchShortcutDisabled && openHatchShortcut == nil
  }

  func setOpenHatchShortcut(_ shortcut: ShortcutDescriptor) {
    openHatchShortcut = shortcut
    isOpenHatchShortcutDisabled = false
    if let data = try? JSONEncoder().encode(shortcut) {
      defaults.set(data, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
    defaults.set(false, forKey: disabledKey)
  }

  func resetOpenHatchShortcutToDefault() {
    openHatchShortcut = nil
    isOpenHatchShortcutDisabled = false
    defaults.removeObject(forKey: key)
    defaults.set(false, forKey: disabledKey)
  }

  func disableOpenHatchShortcut() {
    openHatchShortcut = nil
    isOpenHatchShortcutDisabled = true
    defaults.removeObject(forKey: key)
    defaults.set(true, forKey: disabledKey)
  }

  private func loadShortcut() -> ShortcutDescriptor? {
    guard let data = defaults.data(forKey: key) else {
      return nil
    }
    return try? JSONDecoder().decode(ShortcutDescriptor.self, from: data)
  }
}
