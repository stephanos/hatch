import Foundation

public struct ConfigStore {
  private let fileManager = FileManager.default
  private let environment: ConfigEnvironment

  public init() {
    self.environment = ConfigEnvironment()
  }

  init(environment: ConfigEnvironment) {
    self.environment = environment
  }

  package func paths() throws -> AppPaths {
    let paths = configPaths()
    let workspaceRoot =
      if let customWorkspaceRoot = environment.workspaceRootOverride {
        customWorkspaceRoot
      } else {
        try loadBootstrap().map {
          resolvePath($0.workspaceRoot)
        } ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Workspace")
      }

    return AppPaths(
      bootstrapFile: paths.bootstrapFile,
      workspaceRoot: workspaceRoot,
      hatchRoot: paths.hatchRoot(for: workspaceRoot),
      workspaceConfigFile: paths.workspaceConfigFile(for: workspaceRoot),
      stateDirectory: paths.stateDirectory(for: workspaceRoot),
      cacheDirectory: paths.cacheDirectory(for: workspaceRoot)
    )
  }

  package func loadBootstrap() throws -> BootstrapConfig? {
    let paths = configPaths()
    guard fileManager.fileExists(atPath: paths.bootstrapFile.path) else {
      return nil
    }
    return try decodeBootstrap(from: paths.bootstrapFile)
  }

  package func loadWorkspaceConfig(at paths: AppPaths) throws -> WorkspaceConfig? {
    guard fileManager.fileExists(atPath: paths.workspaceConfigFile.path) else {
      return nil
    }
    return try decodeWorkspace(from: paths.workspaceConfigFile)
  }

  package func saveAll(bootstrap: BootstrapConfig, workspace: WorkspaceConfig) throws {
    let configPaths = configPaths()
    let workspaceRoot = resolvePath(bootstrap.workspaceRoot)
    let paths = AppPaths(
      bootstrapFile: configPaths.bootstrapFile,
      workspaceRoot: workspaceRoot,
      hatchRoot: configPaths.hatchRoot(for: workspaceRoot),
      workspaceConfigFile: configPaths.workspaceConfigFile(for: workspaceRoot),
      stateDirectory: configPaths.stateDirectory(for: workspaceRoot),
      cacheDirectory: configPaths.cacheDirectory(for: workspaceRoot)
    )

    try fileManager.createDirectory(
      at: paths.bootstrapFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(at: paths.hatchRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: paths.cacheDirectory, withIntermediateDirectories: true)

    try encodeBootstrap(bootstrap, to: paths.bootstrapFile)
    try encodeWorkspace(workspace, to: paths.workspaceConfigFile)
  }

  package func loadProjectConfig(projectDirectory: URL) throws -> ProjectConfig? {
    let file = projectConfigFile(in: projectDirectory)
    guard fileManager.fileExists(atPath: file.path) else {
      return nil
    }
    return try decodeProject(from: file)
  }

  package func saveProjectConfig(_ config: ProjectConfig, projectDirectory: URL) throws {
    try encodeProject(config, to: projectConfigFile(in: projectDirectory))
  }

  package func loadRecentProjects(from paths: AppPaths) throws -> [String] {
    let file = recentProjectsFile(in: paths)
    guard fileManager.fileExists(atPath: file.path) else {
      return []
    }
    let data = try Data(contentsOf: file)
    if data.trimmingJSONWhitespace().isEmpty {
      try? fileManager.removeItem(at: file)
      return []
    }
    return try JSONDecoder().decode([String].self, from: data)
  }

  package func saveRecentProjects(_ projects: [String], paths: AppPaths) throws {
    let file = recentProjectsFile(in: paths)
    if projects.isEmpty {
      try? fileManager.removeItem(at: file)
      return
    }
    try encode(projects, to: file)
  }

  private func configPaths() -> ConfigPaths {
    ConfigPaths(configBase: environment.configBase)
  }

  private func projectConfigFile(in projectDirectory: URL) -> URL {
    projectDirectory.appendingPathComponent(ConfigPaths.projectConfigFilename)
  }

  private func recentProjectsFile(in paths: AppPaths) -> URL {
    paths.stateDirectory.appendingPathComponent(ConfigPaths.recentProjectsFilename)
  }

  private func resolvePath(_ value: String) -> URL {
    URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
  }

  private func decode<T: Decodable>(_ type: T.Type, from file: URL) throws -> T {
    let data = try Data(contentsOf: file)
    return try JSONDecoder().decode(type, from: data)
  }

  private func decodeBootstrap(from file: URL) throws -> BootstrapConfig {
    let data = try Data(contentsOf: file)
    if file.pathExtension == "toml" {
      return try TOMLCodec.decodeBootstrap(from: data)
    }
    return try JSONDecoder().decode(BootstrapConfig.self, from: data)
  }

  private func decodeWorkspace(from file: URL) throws -> WorkspaceConfig {
    let data = try Data(contentsOf: file)
    if file.pathExtension == "toml" {
      return try TOMLCodec.decodeWorkspace(from: data)
    }
    return try JSONDecoder().decode(WorkspaceConfig.self, from: data)
  }

  private func decodeProject(from file: URL) throws -> ProjectConfig {
    let data = try Data(contentsOf: file)
    if file.pathExtension == "toml" {
      return try TOMLCodec.decodeProject(from: data)
    }
    return try JSONDecoder().decode(ProjectConfig.self, from: data)
  }

  private func encode<T: Encodable>(_ value: T, to file: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    try data.write(to: file, options: .atomic)
  }

  private func encodeBootstrap(_ value: BootstrapConfig, to file: URL) throws {
    try TOMLCodec.encode(value).write(to: file, options: .atomic)
  }

  private func encodeWorkspace(_ value: WorkspaceConfig, to file: URL) throws {
    try TOMLCodec.encode(value).write(to: file, options: .atomic)
  }

  private func encodeProject(_ value: ProjectConfig, to file: URL) throws {
    try TOMLCodec.encode(value).write(to: file, options: .atomic)
  }
}

extension Data {
  fileprivate func trimmingJSONWhitespace() -> Data {
    let start = firstIndex(where: { !$0.isASCIIWhitespace }) ?? endIndex
    let end = lastIndex(where: { !$0.isASCIIWhitespace }).map(index(after:)) ?? start
    return self[start..<end]
  }
}

extension UInt8 {
  fileprivate var isASCIIWhitespace: Bool {
    switch self {
    case 0x09, 0x0A, 0x0D, 0x20:
      true
    default:
      false
    }
  }
}
