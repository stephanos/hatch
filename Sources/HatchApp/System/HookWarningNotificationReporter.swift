import Foundation
import HatchCore
@preconcurrency import UserNotifications

final class HookWarningNotificationReporter: HookFailureReporter, @unchecked Sendable {
  private let center: UNUserNotificationCenter?

  init(center: UNUserNotificationCenter? = nil) {
    let resolvedCenter =
      center ?? HookWarningNotificationReporter.makeNotificationCenterIfSupported()
    self.center = resolvedCenter
    resolvedCenter?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  func report(_ event: HookFailureEvent) {
    guard let center else { return }

    let content = UNMutableNotificationContent()
    content.title = event.title
    content.subtitle = event.subtitle
    content.body = event.body
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )

    center.add(request)
  }

  private static func makeNotificationCenterIfSupported() -> UNUserNotificationCenter? {
    guard Bundle.main.bundleURL.pathExtension == "app" else {
      return nil
    }
    return .current()
  }
}
