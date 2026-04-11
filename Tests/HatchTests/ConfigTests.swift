import Darwin
import Foundation
import HatchCore

let configTests: [TestCase] = [
  .init(name: "bootstrap TOML round trip includes cli path", run: testBootstrapTomlRoundTripIncludesCliInstallPath),
  .init(name: "workspace TOML round trip preserves hooks", run: testWorkspaceTomlRoundTripPreservesHooks),
  .init(name: "project TOML round trip preserves repo base branches", run: testProjectTomlRoundTripPreservesRepoBaseBranches),
  .init(name: "editor discovery prefers env then installed editors", run: testEditorDiscoveryPrefersEnvThenInstalledEditors),
  .init(name: "config store saveAll writes TOML files", run: testSaveAllWritesTomlFiles),
  .init(name: "config store ignores legacy bootstrap JSON", run: testConfigStoreIgnoresLegacyBootstrapJson),
  .init(name: "config store ignores legacy project JSON", run: testConfigStoreIgnoresLegacyProjectJson),
  .init(name: "config store rejects malformed bootstrap TOML", run: testConfigStoreRejectsMalformedBootstrapToml),
  .init(name: "config store rejects malformed workspace TOML", run: testConfigStoreRejectsMalformedWorkspaceToml),
  .init(name: "config store rejects malformed project TOML", run: testConfigStoreRejectsMalformedProjectToml),
  .init(name: "config store rejects invalid hook name in workspace TOML", run: testConfigStoreRejectsInvalidHookNameInWorkspaceToml),
  .init(name: "config store rejects invalid hook error policy in workspace TOML", run: testConfigStoreRejectsInvalidHookErrorPolicyInWorkspaceToml),
  .init(name: "config store rejects wrong workspace field types in TOML", run: testConfigStoreRejectsWrongWorkspaceFieldTypesInToml),
  .init(name: "config store rejects wrong project field types in TOML", run: testConfigStoreRejectsWrongProjectFieldTypesInToml),
  .init(name: "config store deletes empty recent projects state file", run: testConfigStoreDeletesEmptyRecentProjectsStateFile),
  .init(name: "config store deletes recent projects file when saving empty list", run: testConfigStoreDeletesRecentProjectsFileWhenSavingEmptyList),
]

func testBootstrapTomlRoundTripIncludesCliInstallPath() throws {
  let config = BootstrapConfig(workspaceRoot: "~/Workspace", cliInstallPath: "~/bin")
  let data = TOMLCodec.encode(config)
  let decoded = try TOMLCodec.decodeBootstrap(from: data)
  let source = String(decoding: data, as: UTF8.self)
  try expect(source.contains("workspace_root"), "missing workspace_root TOML key")
  try expect(source.contains("cli_install_path"), "missing cli_install_path TOML key")
  try expect(decoded == config, "bootstrap config round-trip mismatch")
}

func testWorkspaceTomlRoundTripPreservesHooks() throws {
  let config = WorkspaceConfig(
    defaultOrg: "acme",
    defaultRepos: ["api"],
    branchTemplate: "{user}/{task}",
    editor: "zed",
    hooksInclude: ["builtin:auto-create-agent.md"],
    hooks: [.taskPostOpen: HookDefinition(command: ["echo", "hi"], onError: .warn)]
  )
  let data = TOMLCodec.encode(config)
  let decoded = try TOMLCodec.decodeWorkspace(from: data)
  try expect(decoded == config, "workspace config round-trip mismatch")
}

func testProjectTomlRoundTripPreservesRepoBaseBranches() throws {
  let config = ProjectConfig(defaultRepos: ["api"], repoBaseBranches: ["api": "develop"])
  let data = TOMLCodec.encode(config)
  let decoded = try TOMLCodec.decodeProject(from: data)
  let source = String(decoding: data, as: UTF8.self)
  try expect(source.contains("[repo_base_branches]"), "missing repo_base_branches table")
  try expect(decoded == config, "project config round-trip mismatch")
}

func testEditorDiscoveryPrefersEnvThenInstalledEditors() throws {
  let result = EditorDiscovery.discover(
    environment: [
      "VISUAL": "zed",
      "EDITOR": "code"
    ],
    commandExists: { ["zed", "cursor", "code"].contains($0) },
    hasApplication: { $0 == "com.microsoft.VSCode" }
  )

  try expect(result.recommended == "zed", "expected VISUAL to win")
  try expect(
    result.examples == ["zed", "code", "cursor", #"open -a "Visual Studio Code""#],
    "unexpected editor discovery ordering"
  )
}

func testConfigStoreIgnoresLegacyBootstrapJson() throws {
  try withTempDirectory { temp in
    setenv("HATCH_CONFIG_DIR", temp.path, 1)
    defer { unsetenv("HATCH_CONFIG_DIR") }

    try #"{"workspaceRoot":"~/Workspace"}"#.write(
      to: temp.appendingPathComponent("config.json"),
      atomically: true,
      encoding: .utf8
    )

    let config = try ConfigStore().loadBootstrap()
    try expect(config == nil, "legacy bootstrap JSON should be ignored")
  }
}

func testConfigStoreIgnoresLegacyProjectJson() throws {
  try withTempDirectory { root in
    let project = root.appendingPathComponent("alpha", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try #"{"defaultRepos":["api"],"repoBaseBranches":{"api":"develop"}}"#.write(
      to: project.appendingPathComponent("hatch.json"),
      atomically: true,
      encoding: .utf8
    )

    let config = try ConfigStore().loadProjectConfig(projectDirectory: project)
    try expect(config == nil, "legacy project JSON should be ignored")
  }
}

func testSaveAllWritesTomlFiles() throws {
  try withTempDirectory { temp in
    setenv("HATCH_CONFIG_DIR", temp.path, 1)
    defer { unsetenv("HATCH_CONFIG_DIR") }

    let bootstrap = BootstrapConfig(workspaceRoot: temp.appendingPathComponent("Workspace").path, cliInstallPath: "~/.local/bin")
    let workspace = WorkspaceConfig.default
    try ConfigStore().saveAll(bootstrap: bootstrap, workspace: workspace)

    try expect(FileManager.default.fileExists(atPath: temp.appendingPathComponent("config.toml").path), "missing bootstrap TOML")
    let workspaceToml = temp.appendingPathComponent("Workspace/.hatch/config.toml").path
    try expect(FileManager.default.fileExists(atPath: workspaceToml), "missing workspace TOML")
  }
}

func testConfigStoreRejectsMalformedBootstrapToml() throws {
  try withTempDirectory { temp in
    setenv("HATCH_CONFIG_DIR", temp.path, 1)
    defer { unsetenv("HATCH_CONFIG_DIR") }
    try "workspace_root = [".write(
      to: temp.appendingPathComponent("config.toml"),
      atomically: true,
      encoding: .utf8
    )
    try expectThrows(Error.self) {
      _ = try ConfigStore().loadBootstrap()
    }
  }
}

func testConfigStoreRejectsMalformedWorkspaceToml() throws {
  try withTempDirectory { temp in
    setenv("HATCH_CONFIG_DIR", temp.path, 1)
    defer { unsetenv("HATCH_CONFIG_DIR") }
    let workspaceRoot = temp.appendingPathComponent("Workspace", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot.appendingPathComponent(".hatch"), withIntermediateDirectories: true)
    try """
    workspace_root = "\(workspaceRoot.path)"
    cli_install_path = "~/.local/bin"
    """.write(to: temp.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
    try "default_org = [".write(
      to: workspaceRoot.appendingPathComponent(".hatch/config.toml"),
      atomically: true,
      encoding: .utf8
    )
    let paths = try ConfigStore().paths()
    try expectThrows(Error.self) {
      _ = try ConfigStore().loadWorkspaceConfig(at: paths)
    }
  }
}

func testConfigStoreRejectsMalformedProjectToml() throws {
  try withTempDirectory { temp in
    let project = temp.appendingPathComponent("alpha", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try "default_repos = [".write(
      to: project.appendingPathComponent("hatch.toml"),
      atomically: true,
      encoding: .utf8
    )
    try expectThrows(Error.self) {
      _ = try ConfigStore().loadProjectConfig(projectDirectory: project)
    }
  }
}

func testConfigStoreRejectsInvalidHookNameInWorkspaceToml() throws {
  try withTempDirectory { temp in
    setenv("HATCH_CONFIG_DIR", temp.path, 1)
    defer { unsetenv("HATCH_CONFIG_DIR") }
    let workspaceRoot = temp.appendingPathComponent("Workspace", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot.appendingPathComponent(".hatch"), withIntermediateDirectories: true)
    try """
    workspace_root = "\(workspaceRoot.path)"
    cli_install_path = "~/.local/bin"
    """.write(to: temp.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
    try """
    default_org = "acme"
    default_repos = ["api"]
    branch_template = "{user}/{task}"
    editor = "zed"
    hooks_include = []

    [hooks.not_a_real_hook]
    command = ["echo", "hi"]
    on_error = "fail"
    """.write(to: workspaceRoot.appendingPathComponent(".hatch/config.toml"), atomically: true, encoding: .utf8)
    let paths = try ConfigStore().paths()
    try expectThrows(Error.self) {
      _ = try ConfigStore().loadWorkspaceConfig(at: paths)
    }
  }
}

func testConfigStoreRejectsInvalidHookErrorPolicyInWorkspaceToml() throws {
  try withTempDirectory { temp in
    setenv("HATCH_CONFIG_DIR", temp.path, 1)
    defer { unsetenv("HATCH_CONFIG_DIR") }
    let workspaceRoot = temp.appendingPathComponent("Workspace", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot.appendingPathComponent(".hatch"), withIntermediateDirectories: true)
    try """
    workspace_root = "\(workspaceRoot.path)"
    cli_install_path = "~/.local/bin"
    """.write(to: temp.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
    try """
    default_org = "acme"
    default_repos = ["api"]
    branch_template = "{user}/{task}"
    editor = "zed"
    hooks_include = []

    [hooks.task_post_open]
    command = ["echo", "hi"]
    on_error = "explode"
    """.write(to: workspaceRoot.appendingPathComponent(".hatch/config.toml"), atomically: true, encoding: .utf8)
    let paths = try ConfigStore().paths()
    try expectThrows(Error.self) {
      _ = try ConfigStore().loadWorkspaceConfig(at: paths)
    }
  }
}

func testConfigStoreRejectsWrongWorkspaceFieldTypesInToml() throws {
  try withTempDirectory { temp in
    setenv("HATCH_CONFIG_DIR", temp.path, 1)
    defer { unsetenv("HATCH_CONFIG_DIR") }
    let workspaceRoot = temp.appendingPathComponent("Workspace", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot.appendingPathComponent(".hatch"), withIntermediateDirectories: true)
    try """
    workspace_root = "\(workspaceRoot.path)"
    cli_install_path = "~/.local/bin"
    """.write(to: temp.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
    try """
    default_org = 123
    default_repos = "api"
    branch_template = "{user}/{task}"
    editor = "zed"
    hooks_include = []
    """.write(to: workspaceRoot.appendingPathComponent(".hatch/config.toml"), atomically: true, encoding: .utf8)
    let paths = try ConfigStore().paths()
    try expectThrows(Error.self) {
      _ = try ConfigStore().loadWorkspaceConfig(at: paths)
    }
  }
}

func testConfigStoreRejectsWrongProjectFieldTypesInToml() throws {
  try withTempDirectory { temp in
    let project = temp.appendingPathComponent("alpha", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try """
    default_repos = "api"

    [repo_base_branches]
    api = 123
    """.write(to: project.appendingPathComponent("hatch.toml"), atomically: true, encoding: .utf8)
    try expectThrows(Error.self) {
      _ = try ConfigStore().loadProjectConfig(projectDirectory: project)
    }
  }
}

func testConfigStoreDeletesEmptyRecentProjectsStateFile() throws {
  try withTempDirectory { temp in
    setenv("HATCH_CONFIG_DIR", temp.path, 1)
    defer { unsetenv("HATCH_CONFIG_DIR") }

    let workspaceRoot = temp.appendingPathComponent("Workspace", isDirectory: true)
    let hatchRoot = workspaceRoot.appendingPathComponent(".hatch", isDirectory: true)
    let stateDirectory = hatchRoot.appendingPathComponent("state", isDirectory: true)

    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    try """
    workspace_root = "\(workspaceRoot.path)"
    cli_install_path = "~/.local/bin"
    """.write(to: temp.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
    let recentProjectsFile = stateDirectory.appendingPathComponent("recent-projects.json")
    try "".write(
      to: recentProjectsFile,
      atomically: true,
      encoding: .utf8
    )

    let store = ConfigStore()
    let paths = try store.paths()
    let projects = try store.loadRecentProjects(from: paths)

    try expect(projects.isEmpty, "expected empty recent projects for empty state file")
    try expect(
      !FileManager.default.fileExists(atPath: recentProjectsFile.path),
      "expected empty recent projects state file to be deleted"
    )
  }
}

func testConfigStoreDeletesRecentProjectsFileWhenSavingEmptyList() throws {
  try withTempDirectory { temp in
    setenv("HATCH_CONFIG_DIR", temp.path, 1)
    defer { unsetenv("HATCH_CONFIG_DIR") }

    let workspaceRoot = temp.appendingPathComponent("Workspace", isDirectory: true)
    let hatchRoot = workspaceRoot.appendingPathComponent(".hatch", isDirectory: true)
    let stateDirectory = hatchRoot.appendingPathComponent("state", isDirectory: true)

    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    try """
    workspace_root = "\(workspaceRoot.path)"
    cli_install_path = "~/.local/bin"
    """.write(to: temp.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

    let store = ConfigStore()
    let paths = try store.paths()
    let recentProjectsFile = stateDirectory.appendingPathComponent("recent-projects.json")

    try store.saveRecentProjects(["alpha"], paths: paths)
    try expect(
      FileManager.default.fileExists(atPath: recentProjectsFile.path),
      "expected recent projects file after saving non-empty list"
    )

    try store.saveRecentProjects([], paths: paths)
    try expect(
      !FileManager.default.fileExists(atPath: recentProjectsFile.path),
      "expected empty recent projects save to delete file"
    )
  }
}
