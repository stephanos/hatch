import Foundation
import HatchSupport

struct ConfigEnvironment {
  let environment: [String: String]
  let homeDirectory: URL

  init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) {
    self.environment = environment
    self.homeDirectory = homeDirectory
  }

  var configBase: URL {
    if let custom = resolvedURL(for: HatchEnvironment.Key.uiTestConfigDir) {
      return custom
    }
    if let custom = resolvedURL(for: HatchEnvironment.Key.configDir) {
      return custom
    }
    if let xdg = resolvedURL(for: HatchEnvironment.Key.xdgConfigHome) {
      return xdg.appendingPathComponent("hatch")
    }
    return homeDirectory.appendingPathComponent(".config").appendingPathComponent("hatch")
  }

  var workspaceRootOverride: URL? {
    resolvedURL(for: HatchEnvironment.Key.uiTestWorkspaceRoot)
  }

  private func resolvedURL(for key: String) -> URL? {
    guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
  }
}
