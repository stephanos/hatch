import AppKit
import SwiftUI

struct ShortcutPicker: View {
  @ObservedObject private var shortcutStore = ShortcutStore.shared
  @State private var isRecording = false
  @State private var eventMonitor: Any?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Button(isRecording ? "Type Shortcut…" : buttonTitle) {
          isRecording.toggle()
        }
        .buttonStyle(.bordered)

        if isRecording {
          Text("Press a key combination. Esc cancels. Delete disables.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          if !shortcutStore.isUsingDefaultOpenHatchShortcut {
            Button("Use Default") {
              shortcutStore.resetOpenHatchShortcutToDefault()
            }
            .buttonStyle(.plain)
          }

          if shortcutStore.effectiveOpenHatchShortcut != nil {
            Button("Disable") {
              shortcutStore.disableOpenHatchShortcut()
            }
            .buttonStyle(.plain)
          }
        }
      }

      Text(
        "Default: \(ShortcutStore.defaultOpenHatchShortcut.displayString). Use at least one modifier key."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .onChange(of: isRecording) { _, recording in
      if recording {
        startRecording()
      } else {
        stopRecording()
      }
    }
    .onDisappear {
      stopRecording()
    }
  }

  private var buttonTitle: String {
    if let shortcut = shortcutStore.effectiveOpenHatchShortcut {
      return shortcut.displayString
    }
    return "Disabled"
  }

  private func startRecording() {
    stopRecording()

    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handleRecording(event: event)
    }
  }

  private func stopRecording() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
    isRecording = false
  }

  private func handleRecording(event: NSEvent) -> NSEvent? {
    if event.keyCode == 53 {
      stopRecording()
      return nil
    }

    if event.keyCode == 51 || event.keyCode == 117 {
      shortcutStore.disableOpenHatchShortcut()
      stopRecording()
      return nil
    }

    guard let shortcut = ShortcutDescriptor.from(event: event) else {
      return nil
    }

    shortcutStore.setOpenHatchShortcut(shortcut)
    stopRecording()
    return nil
  }
}
