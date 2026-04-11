import Foundation

public struct HookFailureEvent: Sendable {
  public let hookName: HookName
  public let errorPolicy: HookErrorPolicy
  public let message: String
  public let project: String?
  public let task: String?
  public let repoInput: String?

  public init(
    hookName: HookName,
    errorPolicy: HookErrorPolicy,
    message: String,
    project: String?,
    task: String?,
    repoInput: String?
  ) {
    self.hookName = hookName
    self.errorPolicy = errorPolicy
    self.message = message
    self.project = project
    self.task = task
    self.repoInput = repoInput
  }

  public var title: String {
    "hatch hook warning"
  }

  public var subtitle: String {
    hookName.rawValue
  }

  public var body: String {
    let scope =
      [project, task, repoInput]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " / ")

    guard !scope.isEmpty else {
      return message
    }

    return "\(scope): \(message)"
  }
}

public protocol HookFailureReporter: Sendable {
  func report(_ event: HookFailureEvent)
}
