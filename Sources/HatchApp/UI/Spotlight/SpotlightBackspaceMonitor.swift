import AppKit
import SwiftUI

struct SpotlightBackspaceMonitor: NSViewRepresentable {
  let isEnabled: Bool
  let onBackspace: () -> Void
  let onEscape: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.attach(view: view)
    context.coordinator.update(
      isEnabled: isEnabled,
      onBackspace: onBackspace,
      onEscape: onEscape
    )
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.attach(view: nsView)
    context.coordinator.update(
      isEnabled: isEnabled,
      onBackspace: onBackspace,
      onEscape: onEscape
    )
  }

  @MainActor
  final class Coordinator {
    private weak var view: NSView?
    private var monitor: Any?
    private var isEnabled = false
    private var onBackspace: () -> Void = {}
    private var onEscape: () -> Void = {}

    func attach(view: NSView) {
      self.view = view
      installMonitorIfNeeded()
    }

    func update(
      isEnabled: Bool,
      onBackspace: @escaping () -> Void,
      onEscape: @escaping () -> Void
    ) {
      self.isEnabled = isEnabled
      self.onBackspace = onBackspace
      self.onEscape = onEscape
      installMonitorIfNeeded()
    }

    private func installMonitorIfNeeded() {
      guard monitor == nil else {
        return
      }

      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, self.isEnabled else {
          if event.keyCode == 53 {
            self?.onEscape()
            return nil
          }
          return event
        }
        if event.keyCode == 53 {
          self.onEscape()
          return nil
        }
        guard event.keyCode == 51 || event.keyCode == 117 else {
          return event
        }
        guard let window = self.view?.window, window == NSApp.keyWindow else {
          return event
        }

        self.onBackspace()
        return nil
      }
    }
  }
}
