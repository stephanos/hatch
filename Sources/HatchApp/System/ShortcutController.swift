import Carbon
import Combine
import SwiftUI

@MainActor
final class ShortcutController: ObservableObject {
  private let windowController: WindowActivationController
  private let shortcutStore: ShortcutStore
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var cancellable: AnyCancellable?

  private let signature: OSType = 0x6861_7463
  private let hotKeyID: UInt32 = 1

  init(
    windowController: WindowActivationController,
    shortcutStore: ShortcutStore = .shared
  ) {
    self.windowController = windowController
    self.shortcutStore = shortcutStore

    installHandlerIfNeeded()
    register(shortcutStore.effectiveOpenHatchShortcut)

    cancellable = shortcutStore.$openHatchShortcut
      .combineLatest(shortcutStore.$isOpenHatchShortcutDisabled)
      .sink { [weak self] _, _ in
        self?.register(shortcutStore.effectiveOpenHatchShortcut)
      }
  }

  private func installHandlerIfNeeded() {
    guard eventHandler == nil else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData else { return noErr }
        let controller = Unmanaged<ShortcutController>
          .fromOpaque(userData)
          .takeUnretainedValue()
        controller.handle(event: event)
        return noErr
      },
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
  }

  private func handle(event: EventRef?) {
    guard let event else { return }

    var hotKey = EventHotKeyID()
    GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &hotKey
    )

    guard hotKey.signature == signature, hotKey.id == hotKeyID else {
      return
    }

    windowController.openCommandPalette()
  }

  private func register(_ shortcut: ShortcutDescriptor?) {
    unregister()

    guard let shortcut else {
      return
    }

    let hotKeyID = EventHotKeyID(signature: signature, id: self.hotKeyID)
    RegisterEventHotKey(
      UInt32(shortcut.keyCode),
      shortcut.carbonModifierFlags,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
  }

  private func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
  }
}
