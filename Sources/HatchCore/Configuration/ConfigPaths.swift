import Foundation

struct ConfigPaths {
  static let bootstrapFilename = "config.toml"
  static let workspaceConfigFilename = "config.toml"
  static let projectConfigFilename = "hatch.toml"
  static let hatchDirectoryName = ".hatch"
  static let stateDirectoryName = "state"
  static let cacheDirectoryName = "cache"
  static let recentProjectsFilename = "recent-projects.json"

  let configBase: URL

  var bootstrapFile: URL {
    configBase.appendingPathComponent(Self.bootstrapFilename)
  }

  func hatchRoot(for workspaceRoot: URL) -> URL {
    workspaceRoot.appendingPathComponent(Self.hatchDirectoryName)
  }

  func workspaceConfigFile(for workspaceRoot: URL) -> URL {
    hatchRoot(for: workspaceRoot).appendingPathComponent(Self.workspaceConfigFilename)
  }

  func stateDirectory(for workspaceRoot: URL) -> URL {
    hatchRoot(for: workspaceRoot).appendingPathComponent(Self.stateDirectoryName)
  }

  func cacheDirectory(for workspaceRoot: URL) -> URL {
    hatchRoot(for: workspaceRoot).appendingPathComponent(Self.cacheDirectoryName)
  }
}
