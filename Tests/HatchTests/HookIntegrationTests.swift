import Foundation
import HatchCore

let hookIntegrationTests: [TestCase] = [
  .init(name: "integration builtin hooks create claude files", run: testIntegrationBuiltinHooksCreateClaudeFiles),
  .init(name: "integration builtin hooks create claude files for default repos", run: testIntegrationBuiltinHooksCreateClaudeFilesForDefaultRepos),
  .init(name: "integration builtin hook file collision aborts operation", run: testIntegrationBuiltinHookFileCollisionAbortsOperation),
  .init(name: "integration explicit repo hook overrides builtin claude hook", run: testIntegrationExplicitRepoHookOverridesBuiltinClaudeHook),
  .init(name: "integration empty command hook aborts operation", run: testIntegrationEmptyCommandHookAbortsOperation),
  .init(name: "integration project pre create hook receives env", run: testIntegrationProjectPreCreateHookReceivesEnv),
  .init(name: "integration task post open hook receives env", run: testIntegrationTaskPostOpenHookReceivesEnv),
  .init(name: "integration repo post add hook receives env", run: testIntegrationRepoPostAddHookReceivesEnv),
  .init(name: "integration repo post add failure rolls back repo", run: testIntegrationRepoPostAddFailureRollsBackRepo),
  .init(name: "integration fail hook aborts operation", run: testIntegrationFailHookAbortsOperation),
  .init(name: "integration ignore hook allows operation", run: testIntegrationIgnoreHookAllowsOperation),
  .init(name: "integration warn hook allows operation", run: testIntegrationWarnHookAllowsOperation),
  .init(name: "integration warn hook reports notification event", run: testIntegrationWarnHookReportsNotificationEvent),
]

func testIntegrationBuiltinHooksCreateClaudeFiles() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: [],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: ["builtin:auto-create-agent.md"],
      hooks: [:]
    )
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    var state = try behavior.loadAppState()
    let project = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    let projectAgents = project.path.appendingPathComponent("AGENTS.md")
    let projectClaude = project.path.appendingPathComponent("CLAUDE.md")
    let projectAgentsContents = try String(contentsOf: projectAgents, encoding: .utf8)
    let projectClaudeContents = try String(contentsOf: projectClaude, encoding: .utf8)
    try expect(FileManager.default.fileExists(atPath: projectAgents.path), "expected project AGENTS.md")
    try expect(FileManager.default.fileExists(atPath: projectClaude.path), "expected project CLAUDE.md")
    try expect(
      projectAgentsContents == "## Project Instructions\n",
      "expected project AGENTS.md content"
    )
    try expect(
      projectClaudeContents == "@AGENTS.md\n",
      "expected project CLAUDE.md to reference AGENTS.md"
    )
    state = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: config)
    let taskAgents = task.path.appendingPathComponent("AGENTS.md")
    let taskClaude = task.path.appendingPathComponent("CLAUDE.md")
    let taskLocalClaude = task.path.appendingPathComponent("CLAUDE.local.md")
    let taskAgentsContents = try String(contentsOf: taskAgents, encoding: .utf8)
    let taskClaudeContents = try String(contentsOf: taskClaude, encoding: .utf8)
    let taskLocalClaudeContents = try String(contentsOf: taskLocalClaude, encoding: .utf8)
    try expect(FileManager.default.fileExists(atPath: taskAgents.path), "expected task AGENTS.md")
    try expect(FileManager.default.fileExists(atPath: taskClaude.path), "expected task CLAUDE.md")
    try expect(FileManager.default.fileExists(atPath: taskLocalClaude.path), "expected task CLAUDE.local.md")
    try expect(
      taskAgentsContents == "## Task Instructions\n",
      "expected task AGENTS.md content"
    )
    try expect(
      taskClaudeContents == "@AGENTS.md\n",
      "expected task CLAUDE.md to reference AGENTS.md"
    )
    try expect(
      taskLocalClaudeContents == "@AGENTS.md\n",
      "expected task CLAUDE.local.md to reference AGENTS.md"
    )
    let projectSummary = ProjectSummary(name: "alpha", path: project.path)
    try behavior.addRepo(
      repoInput: "web",
      taskDirectory: task.path,
      projectConfig: try behavior.loadProjectConfig(for: projectSummary),
      paths: state.paths,
      config: config,
      force: false
    )
    let repoPath = task.path.appendingPathComponent("web")
    let repoAgents = repoPath.appendingPathComponent("AGENTS.md")
    let repoClaude = repoPath.appendingPathComponent("CLAUDE.md")
    let repoAgentsContents = try String(contentsOf: repoAgents, encoding: .utf8)
    let repoClaudeContents = try String(contentsOf: repoClaude, encoding: .utf8)
    try expect(FileManager.default.fileExists(atPath: repoAgents.path), "expected repo AGENTS.md")
    try expect(FileManager.default.fileExists(atPath: repoClaude.path), "expected repo CLAUDE.md")
    try expect(
      repoAgentsContents == "## Repo Instructions\n",
      "expected repo AGENTS.md content"
    )
    try expect(
      repoClaudeContents == "@AGENTS.md\n",
      "expected repo CLAUDE.md to reference AGENTS.md"
    )
  }
}

func testIntegrationBuiltinHooksCreateClaudeFilesForDefaultRepos() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: ["web"],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: ["builtin:auto-create-agent.md"],
      hooks: [:]
    )
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    state = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: config)
    let defaultRepoClaudeContents = try String(
      contentsOf: task.path.appendingPathComponent("web/CLAUDE.md"),
      encoding: .utf8
    )

    try expect(
      FileManager.default.fileExists(atPath: task.path.appendingPathComponent("web/AGENTS.md").path),
      "expected default repo AGENTS.md"
    )
    try expect(
      FileManager.default.fileExists(atPath: task.path.appendingPathComponent("web/CLAUDE.md").path),
      "expected default repo CLAUDE.md"
    )
    try expect(
      defaultRepoClaudeContents == "@AGENTS.md\n",
      "expected default repo CLAUDE.md to reference AGENTS.md"
    )
  }
}

func testIntegrationBuiltinHookFileCollisionAbortsOperation() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: [],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: ["builtin:auto-create-agent.md"],
      hooks: [:]
    )
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    state = try behavior.loadAppState()
    let projectPath = env.workspaceRoot.appendingPathComponent("alpha")
    let taskPath = projectPath.appendingPathComponent("one")
    try FileManager.default.createDirectory(at: taskPath, withIntermediateDirectories: true)
    try "existing".write(to: taskPath.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    try expectThrows(HatchError.self) {
      _ = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: config)
    }
  }
}

func testIntegrationExplicitRepoHookOverridesBuiltinClaudeHook() throws {
  try withIntegrationEnvironment { env in
    let marker = env.root.appendingPathComponent("repo-hook-ran.txt")
    try writeExecutable(at: env.binDir.appendingPathComponent("hook-repo-only"), body: """
    #!/bin/sh
    printf 'repo-hook\\n' > "\(marker.path)"
    """)
    let behavior = LiveHatchBehavior()
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: [],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: ["builtin:auto-create-agent.md"],
      hooks: [.repoPostAdd: HookDefinition(command: ["hook-repo-only"], onError: .fail)]
    )
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    var state = try behavior.loadAppState()
    let project = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    state = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: config)
    let projectSummary = ProjectSummary(name: "alpha", path: project.path)
    try behavior.addRepo(
      repoInput: "web",
      taskDirectory: task.path,
      projectConfig: try behavior.loadProjectConfig(for: projectSummary),
      paths: state.paths,
      config: config,
      force: false
    )
    try expect(FileManager.default.fileExists(atPath: marker.path), "expected explicit repo hook to run")
    try expect(!FileManager.default.fileExists(atPath: task.path.appendingPathComponent("web/AGENTS.md").path), "expected builtin repo AGENTS.md to be overridden")
    try expect(!FileManager.default.fileExists(atPath: task.path.appendingPathComponent("web/CLAUDE.md").path), "expected builtin repo hook to be overridden")
  }
}

func testIntegrationEmptyCommandHookAbortsOperation() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: env.workspaceConfig.defaultRepos,
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [.projectPreCreate: HookDefinition(command: [], onError: .fail)]
    )
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    let state = try behavior.loadAppState()
    try expectThrows(HatchError.self) {
      _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    }
  }
}

func testIntegrationProjectPreCreateHookReceivesEnv() throws {
  try withIntegrationEnvironment { env in
    let log = env.root.appendingPathComponent("project-hook.log")
    try writeExecutable(at: env.binDir.appendingPathComponent("hook-project"), body: """
    #!/bin/sh
    printf '%s|%s|%s\\n' "$HATCH_PROJECT" "$HATCH_PROJECT_PATH" "$HATCH_WORKSPACE_ROOT" > "\(log.path)"
    """)
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: env.workspaceConfig.defaultRepos,
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [.projectPreCreate: HookDefinition(command: ["hook-project"], onError: .fail)]
    )
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    let output = try String(contentsOf: log, encoding: .utf8)
    try expect(output.contains("alpha|"), "expected project hook env output")
  }
}

func testIntegrationTaskPostOpenHookReceivesEnv() throws {
  try withIntegrationEnvironment { env in
    let log = env.root.appendingPathComponent("task-hook.log")
    try writeExecutable(at: env.binDir.appendingPathComponent("hook-task"), body: """
    #!/bin/sh
    printf '%s|%s\\n' "$HATCH_TASK" "$HATCH_TASK_PATH" >> "\(log.path)"
    """)
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: env.workspaceConfig.defaultRepos,
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [.taskPostOpen: HookDefinition(command: ["hook-task"], onError: .fail)]
    )
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    state = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: config)
    let output = try String(contentsOf: log, encoding: .utf8)
    try expect(output.contains("one|\(task.path.path)"), "expected task hook env output")
  }
}

func testIntegrationRepoPostAddHookReceivesEnv() throws {
  try withIntegrationEnvironment { env in
    let log = env.root.appendingPathComponent("repo-hook.log")
    try writeExecutable(at: env.binDir.appendingPathComponent("hook-repo"), body: """
    #!/bin/sh
    printf '%s|%s\\n' "$HATCH_REPO_INPUT" "$HATCH_REPO_PATH" >> "\(log.path)"
    """)
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: [],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [.repoPostAdd: HookDefinition(command: ["hook-repo"], onError: .fail)]
    )
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    state = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: config)
    let project = ProjectSummary(name: "alpha", path: env.workspaceRoot.appendingPathComponent("alpha"))
    try behavior.addRepo(
      repoInput: "web",
      taskDirectory: task.path,
      projectConfig: try behavior.loadProjectConfig(for: project),
      paths: state.paths,
      config: config,
      force: false
    )
    let output = try String(contentsOf: log, encoding: .utf8)
    try expect(output.contains("web|\(task.path.appendingPathComponent("web").path)"), "expected repo hook env output")
  }
}

func testIntegrationRepoPostAddFailureRollsBackRepo() throws {
  try withIntegrationEnvironment { env in
    try writeExecutable(at: env.binDir.appendingPathComponent("hook-repo-fail"), body: "#!/bin/sh\nexit 1\n")
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: [],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [.repoPostAdd: HookDefinition(command: ["hook-repo-fail"], onError: .fail)]
    )
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    state = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: config)
    let project = ProjectSummary(name: "alpha", path: env.workspaceRoot.appendingPathComponent("alpha"))
    let repoPath = task.path.appendingPathComponent("web")
    try expectThrows(HatchError.self) {
      try behavior.addRepo(
        repoInput: "web",
        taskDirectory: task.path,
        projectConfig: try behavior.loadProjectConfig(for: project),
        paths: state.paths,
        config: config,
        force: false
      )
    }
    try expect(!FileManager.default.fileExists(atPath: repoPath.path), "expected failed repo post hook to remove repo checkout")
  }
}

func testIntegrationFailHookAbortsOperation() throws {
  try withIntegrationEnvironment { env in
    try writeExecutable(at: env.binDir.appendingPathComponent("hook-fail"), body: "#!/bin/sh\nexit 1\n")
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: env.workspaceConfig.defaultRepos,
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [.projectPreCreate: HookDefinition(command: ["hook-fail"], onError: .fail)]
    )
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    let state = try behavior.loadAppState()
    try expectThrows(HatchError.self) {
      _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    }
  }
}

func testIntegrationIgnoreHookAllowsOperation() throws {
  try withIntegrationEnvironment { env in
    try writeExecutable(at: env.binDir.appendingPathComponent("hook-ignore"), body: "#!/bin/sh\nexit 1\n")
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: env.workspaceConfig.defaultRepos,
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [.projectPreCreate: HookDefinition(command: ["hook-ignore"], onError: .ignore)]
    )
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    let state = try behavior.loadAppState()
    let project = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    try expect(FileManager.default.fileExists(atPath: project.path.path), "expected project to be created despite ignore hook")
  }
}

func testIntegrationWarnHookAllowsOperation() throws {
  try withIntegrationEnvironment { env in
    try writeExecutable(at: env.binDir.appendingPathComponent("hook-warn"), body: "#!/bin/sh\nexit 1\n")
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: env.workspaceConfig.defaultRepos,
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [.projectPreCreate: HookDefinition(command: ["hook-warn"], onError: .warn)]
    )
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    let state = try behavior.loadAppState()
    let project = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    try expect(FileManager.default.fileExists(atPath: project.path.path), "expected project to be created despite warn hook")
  }
}

func testIntegrationWarnHookReportsNotificationEvent() throws {
  try withIntegrationEnvironment { env in
    try writeExecutable(at: env.binDir.appendingPathComponent("hook-warn"), body: "#!/bin/sh\nexit 1\n")
    let reporter = RecordingHookFailureReporter()
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: env.workspaceConfig.defaultRepos,
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [.projectPreCreate: HookDefinition(command: ["hook-warn"], onError: .warn)]
    )
    let behavior = LiveHatchBehavior(hookFailureReporter: reporter)
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    try expect(reporter.events.count == 1, "expected warn hook failure to be reported")
    try expect(reporter.events[0].hookName == .projectPreCreate, "expected reported hook name")
    try expect(reporter.events[0].project == "alpha", "expected reported project context")
  }
}

private final class RecordingHookFailureReporter: HookFailureReporter, @unchecked Sendable {
  private(set) var events: [HookFailureEvent] = []

  func report(_ event: HookFailureEvent) {
    events.append(event)
  }
}
