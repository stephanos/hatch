import Foundation

public struct BootstrapConfig: Codable, Equatable, Sendable {
  public var workspaceRoot: String
  public var cliInstallPath: String

  public init(workspaceRoot: String, cliInstallPath: String = "~/.local/bin") {
    self.workspaceRoot = workspaceRoot
    self.cliInstallPath = cliInstallPath
  }

  enum CodingKeys: String, CodingKey {
    case workspaceRoot
    case cliInstallPath
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    workspaceRoot = try container.decode(String.self, forKey: .workspaceRoot)
    cliInstallPath =
      try container.decodeIfPresent(String.self, forKey: .cliInstallPath)
      ?? "~/.local/bin"
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(workspaceRoot, forKey: .workspaceRoot)
    try container.encode(cliInstallPath, forKey: .cliInstallPath)
  }
}
