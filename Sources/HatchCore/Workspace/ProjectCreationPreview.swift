import Foundation

public struct ProjectCreationPreview: Equatable, Sendable {
  public let project: String
  public let projectDirectory: URL
  public let configFile: URL

  public init(
    project: String,
    projectDirectory: URL,
    configFile: URL
  ) {
    self.project = project
    self.projectDirectory = projectDirectory
    self.configFile = configFile
  }
}
