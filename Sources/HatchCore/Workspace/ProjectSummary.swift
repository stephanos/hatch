import Foundation

public struct ProjectSummary: Identifiable, Hashable, Sendable {
  public var id: String { name }
  public let name: String
  public let path: URL

  public init(name: String, path: URL) {
    self.name = name
    self.path = path
  }
}
