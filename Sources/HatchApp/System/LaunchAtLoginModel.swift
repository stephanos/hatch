import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginModel: ObservableObject {
  @Published private(set) var isEnabled = false

  private let preferenceKey = "launchAtLoginPreferenceSet"

  init() {
    refresh()
  }

  func toggle() {
    setEnabled(!isEnabled)
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      UserDefaults.standard.set(true, forKey: preferenceKey)
      refresh()
    } catch {
      NSLog("Failed to update launch at login: \(error.localizedDescription)")
      refresh()
    }
  }

  func refresh() {
    switch SMAppService.mainApp.status {
    case .enabled:
      isEnabled = true
    case .notRegistered, .notFound, .requiresApproval:
      isEnabled = false
    @unknown default:
      isEnabled = false
    }
  }

  func configureDefaultIfNeeded() {
    guard !UserDefaults.standard.bool(forKey: preferenceKey) else {
      return
    }
    setEnabled(true)
  }
}
