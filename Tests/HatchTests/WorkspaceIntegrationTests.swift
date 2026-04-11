import Foundation
import HatchCore

let workspaceIntegrationTests: [TestCase] = [
  .init(name: "integration create project writes marker and config", run: testIntegrationCreateProjectWritesMarkerAndConfig),
  .init(name: "integration create task clones default repo and opens editor", run: testIntegrationCreateTaskClonesDefaultRepoAndOpensEditor),
  .init(name: "integration add repo force replaces existing checkout", run: testIntegrationAddRepoForceReplacesExistingCheckout),
  .init(name: "integration save configuration installs cli symlink", run: testIntegrationSaveConfigurationInstallsCLISymlink),
  .init(name: "integration recent projects reorder without duplicates", run: testIntegrationRecentProjectsReorderWithoutDuplicates),
  .init(name: "integration clone failure rolls back task creation", run: testIntegrationCloneFailureRollsBackTaskCreation),
  .init(name: "integration missing base branch surfaces error", run: testIntegrationMissingBaseBranchSurfacesError),
  .init(name: "integration missing base branch rolls back repo creation", run: testIntegrationMissingBaseBranchRollsBackRepoCreation),
  .init(name: "integration editor failure rolls back task creation", run: testIntegrationEditorFailureRollsBackTaskCreation),
  .init(name: "integration editor command parsing supports quotes and spaces", run: testIntegrationEditorCommandParsingSupportsQuotesAndSpaces),
  .init(name: "integration project identifier validation rejects invalid names", run: testIntegrationProjectIdentifierValidationRejectsInvalidNames),
  .init(name: "integration task identifier validation rejects invalid names", run: testIntegrationTaskIdentifierValidationRejectsInvalidNames),
  .init(name: "integration branch template validation rejects empty value", run: testIntegrationBranchTemplateValidationRejectsEmptyValue),
  .init(name: "integration workspace root with spaces works", run: testIntegrationWorkspaceRootWithSpacesWorks),
]

func testIntegrationCreateProjectWritesMarkerAndConfig() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()

    let project = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)

    try expect(FileManager.default.fileExists(atPath: project.path.appendingPathComponent(".project").path), "missing project marker")
    try expect(FileManager.default.fileExists(atPath: project.path.appendingPathComponent("hatch.toml").path), "missing project config")
  }
}

func testIntegrationCreateTaskClonesDefaultRepoAndOpensEditor() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)

    let refreshed = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "task-a", paths: refreshed.paths, config: env.workspaceConfig)

    let repoPath = task.path.appendingPathComponent("api")
    try expect(FileManager.default.fileExists(atPath: repoPath.appendingPathComponent(".git").path), "expected default repo checkout")
    let branch = try String(contentsOf: repoPath.appendingPathComponent(".branch"), encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    try expect(branch == "\(NSUserName())/task-a" || branch.hasSuffix("/task-a"), "expected task branch to be checked out")

    let editorLog = try String(contentsOf: env.editorLog, encoding: .utf8)
    try expect(editorLog.contains(task.path.path), "expected editor to open task path")

    let finalState = try behavior.loadAppState()
    try expect(finalState.recentProjects.first == "alpha", "expected project to be marked recent")
  }
}

func testIntegrationAddRepoForceReplacesExistingCheckout() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let refreshed = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "task-a", paths: refreshed.paths, config: env.workspaceConfig)
    let project = ProjectSummary(name: "alpha", path: env.workspaceRoot.appendingPathComponent("alpha"))
    let projectConfig = try behavior.loadProjectConfig(for: project)

    let repoPath = task.path.appendingPathComponent("api")
    try "stale".write(to: repoPath.appendingPathComponent("stale.txt"), atomically: true, encoding: .utf8)

    try behavior.addRepo(
      repoInput: "api",
      taskDirectory: task.path,
      projectConfig: projectConfig,
      paths: refreshed.paths,
      config: env.workspaceConfig,
      force: true
    )

    try expect(!FileManager.default.fileExists(atPath: repoPath.appendingPathComponent("stale.txt").path), "expected stale checkout contents to be removed")
    let cloneURL = try String(contentsOf: repoPath.appendingPathComponent(".clone_url"), encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    try expect(cloneURL == "https://github.com/acme/api.git", "expected repo clone URL")
  }
}

func testIntegrationSaveConfigurationInstallsCLISymlink() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let installed = env.binDir.appendingPathComponent("hatch")
    try expect(FileManager.default.fileExists(atPath: installed.path), "expected saveConfiguration to install hatch symlink")
    try expect(installed.resolvingSymlinksInPath().lastPathComponent == "hatch-cli", "expected installed symlink to point at hatch-cli")
  }
}

func testIntegrationRecentProjectsReorderWithoutDuplicates() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "beta", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    let taskA = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    _ = try behavior.createTask(project: "beta", task: "two", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    try behavior.openTask(taskA, paths: state.paths, config: env.workspaceConfig)
    let final = try behavior.loadAppState()
    try expect(final.recentProjects == ["alpha", "beta"], "expected recent projects reorder without duplicates")
  }
}

func testIntegrationCloneFailureRollsBackTaskCreation() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    try withEnvironment(["GIT_FAIL_CLONE": "1"]) {
      let refreshed = try behavior.loadAppState()
      try expectThrows(HatchError.self) {
        _ = try behavior.createTask(project: "alpha", task: "one", paths: refreshed.paths, config: env.workspaceConfig)
      }
      try expect(!FileManager.default.fileExists(atPath: env.workspaceRoot.appendingPathComponent("alpha/one").path), "expected failed task creation to remove task directory")
    }
  }
}

func testIntegrationMissingBaseBranchSurfacesError() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    let emptyConfig = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: [],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [:]
    )
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: emptyConfig)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: emptyConfig)
    state = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: emptyConfig)
    let projectConfig = ProjectConfig(defaultRepos: [], repoBaseBranches: ["web": "release/1"])
    try withEnvironment(["GIT_MISSING_BRANCHES": "refs/remotes/origin/release/1"]) {
      try expectThrows(HatchError.self) {
        try behavior.addRepo(
          repoInput: "web",
          taskDirectory: task.path,
          projectConfig: projectConfig,
          paths: state.paths,
          config: emptyConfig,
          force: false
        )
      }
    }
  }
}

func testIntegrationMissingBaseBranchRollsBackRepoCreation() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    let emptyConfig = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: [],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [:]
    )
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: emptyConfig)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: emptyConfig)
    state = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: emptyConfig)
    let projectConfig = ProjectConfig(defaultRepos: [], repoBaseBranches: ["web": "release/1"])
    let repoPath = task.path.appendingPathComponent("web")
    try withEnvironment(["GIT_MISSING_BRANCHES": "refs/remotes/origin/release/1"]) {
      try expectThrows(HatchError.self) {
        try behavior.addRepo(
          repoInput: "web",
          taskDirectory: task.path,
          projectConfig: projectConfig,
          paths: state.paths,
          config: emptyConfig,
          force: false
        )
      }
      try expect(!FileManager.default.fileExists(atPath: repoPath.path), "expected failed repo add to remove checkout directory")
    }
  }
}

func testIntegrationEditorFailureRollsBackTaskCreation() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    try withEnvironment(["EDITOR_FAIL": "1"]) {
      let refreshed = try behavior.loadAppState()
      try expectThrows(HatchError.self) {
        _ = try behavior.createTask(project: "alpha", task: "one", paths: refreshed.paths, config: env.workspaceConfig)
      }
      try expect(!FileManager.default.fileExists(atPath: env.workspaceRoot.appendingPathComponent("alpha/one").path), "expected failed editor launch to remove task directory")
    }
  }
}

func testIntegrationEditorCommandParsingSupportsQuotesAndSpaces() throws {
  try withIntegrationEnvironment { env in
    let editorDir = env.root.appendingPathComponent("Editor Bin", isDirectory: true)
    try FileManager.default.createDirectory(at: editorDir, withIntermediateDirectories: true)
    let editorPath = editorDir.appendingPathComponent("log editor")
    let log = env.root.appendingPathComponent("custom-editor.log")
    try writeExecutable(at: editorPath, body: """
    #!/bin/sh
    printf '%s|%s\\n' "$1" "$2" >> "\(log.path)"
    """)
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: [],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: "\"\(editorPath.path)\" --wait",
      hooksInclude: [],
      hooks: [:]
    )
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    let refreshed = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "one", paths: refreshed.paths, config: config)
    let output = try String(contentsOf: log, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    try expect(output == "--wait|\(task.path.path)", "expected quoted editor command to preserve executable path and arguments")
  }
}

func testIntegrationProjectIdentifierValidationRejectsInvalidNames() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    try expectThrows(HatchError.self) {
      _ = try behavior.createProject(name: "bad name", paths: state.paths, config: env.workspaceConfig)
    }
    try expectThrows(HatchError.self) {
      _ = try behavior.createProject(name: "   ", paths: state.paths, config: env.workspaceConfig)
    }
  }
}

func testIntegrationTaskIdentifierValidationRejectsInvalidNames() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let refreshed = try behavior.loadAppState()
    try expectThrows(HatchError.self) {
      _ = try behavior.createTask(project: "alpha", task: "bad name", paths: refreshed.paths, config: env.workspaceConfig)
    }
    try expectThrows(HatchError.self) {
      _ = try behavior.createTask(project: "alpha", task: "   ", paths: refreshed.paths, config: env.workspaceConfig)
    }
  }
}

func testIntegrationBranchTemplateValidationRejectsEmptyValue() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    let invalid = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: env.workspaceConfig.defaultRepos,
      branchTemplate: "   ",
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [:]
    )
    try expectThrows(HatchError.self) {
      _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: invalid)
    }
  }
}

func testIntegrationWorkspaceRootWithSpacesWorks() throws {
  try withNamedIntegrationEnvironment(rootName: "Sandbox With Spaces") { env in
    let behavior = LiveHatchBehavior()
    let bootstrap = BootstrapConfig(workspaceRoot: env.root.appendingPathComponent("Workspace Root With Spaces").path, cliInstallPath: env.root.appendingPathComponent("bin dir with spaces").path)
    _ = try behavior.saveConfiguration(bootstrap: bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    let project = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    try expect(project.path.path.contains("Workspace Root With Spaces"), "expected workspace path with spaces")
    try expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: NSString(string: bootstrap.cliInstallPath).expandingTildeInPath).appendingPathComponent("hatch").path), "expected cli install path with spaces")
  }
}
