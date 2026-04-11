import Foundation

public struct AppPaths: Sendable {
  public let bootstrapFile: URL
  public let workspaceRoot: URL
  public let hatchRoot: URL
  public let workspaceConfigFile: URL
  public let stateDirectory: URL
  public let cacheDirectory: URL

  public init(
    bootstrapFile: URL,
    workspaceRoot: URL,
    hatchRoot: URL,
    workspaceConfigFile: URL,
    stateDirectory: URL,
    cacheDirectory: URL
  ) {
    self.bootstrapFile = bootstrapFile
    self.workspaceRoot = workspaceRoot
    self.hatchRoot = hatchRoot
    self.workspaceConfigFile = workspaceConfigFile
    self.stateDirectory = stateDirectory
    self.cacheDirectory = cacheDirectory
  }
}
