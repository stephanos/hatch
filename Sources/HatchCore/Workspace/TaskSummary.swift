import Foundation

public struct TaskSummary: Identifiable, Hashable, Sendable {
  public var id: String { "\(project)/\(task)" }
  public let project: String
  public let task: String
  public let path: URL

  public init(project: String, task: String, path: URL) {
    self.project = project
    self.task = task
    self.path = path
  }
}
