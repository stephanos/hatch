import Foundation
import HatchCLIKit
import HatchCore

let cliIntegrationTests: [TestCase] = [
  .init(name: "cli subprocess help exits zero", run: testCLISubprocessHelp),
  .init(name: "cli subprocess help flags exit zero", run: testCLISubprocessHelpFlags),
  .init(name: "cli subprocess project list empty prints nothing", run: testCLISubprocessProjectListEmpty),
  .init(name: "cli subprocess completions init zsh writes startup block", run: testCLISubprocessCompletionsInitZsh),
  .init(name: "cli subprocess completions init zsh is idempotent", run: testCLISubprocessCompletionsInitZshIdempotent),
  .init(name: "cli subprocess project command with no subcommand prints usage error", run: testCLISubprocessProjectCommandWithoutSubcommand),
  .init(name: "cli subprocess task command with no subcommand prints usage error", run: testCLISubprocessTaskCommandWithoutSubcommand),
  .init(name: "cli subprocess task resume prints task path", run: testCLISubprocessTaskResume),
  .init(name: "cli subprocess task resume no match exits non zero", run: testCLISubprocessTaskResumeNoMatch),
  .init(name: "cli subprocess task resume ambiguity exits non zero", run: testCLISubprocessTaskResumeAmbiguity),
  .init(name: "cli subprocess unknown command exits non zero", run: testCLISubprocessUnknownCommandFails),
  .init(name: "cli subprocess project alias works", run: testCLISubprocessProjectAliasWorks),
  .init(name: "cli subprocess task alias works", run: testCLISubprocessTaskAliasWorks),
  .init(name: "cli subprocess project create duplicate exits non zero", run: testCLISubprocessProjectCreateDuplicateFails),
  .init(name: "cli subprocess project create wrong arity prints usage error", run: testCLISubprocessProjectCreateWrongArity),
  .init(name: "cli subprocess task create missing project exits non zero", run: testCLISubprocessTaskCreateMissingProjectFails),
  .init(name: "cli subprocess task create wrong arity prints usage error", run: testCLISubprocessTaskCreateWrongArity),
  .init(name: "cli subprocess task list empty prints nothing", run: testCLISubprocessTaskListEmpty),
  .init(name: "cli subprocess task list filters by project", run: testCLISubprocessTaskListFiltersByProject),
  .init(name: "cli subprocess project config opens editor", run: testCLISubprocessProjectConfigOpensEditor),
  .init(name: "cli subprocess project config recreates missing file", run: testCLISubprocessProjectConfigRecreatesMissingFile),
  .init(name: "cli subprocess project config wrong arity prints usage error", run: testCLISubprocessProjectConfigWrongArity),
  .init(name: "cli subprocess project config missing project exits non zero", run: testCLISubprocessProjectConfigMissingProjectFails),
  .init(name: "cli subprocess checkout clones repo from task dir", run: testCLISubprocessCheckout),
  .init(name: "cli subprocess checkout outside task exits non zero", run: testCLISubprocessCheckoutOutsideTaskFails),
  .init(name: "cli subprocess checkout failure reports stderr", run: testCLISubprocessCheckoutFailure),
  .init(name: "cli subprocess task clean interactive prompt works", run: testCLISubprocessTaskCleanInteractive),
  .init(name: "cli subprocess task clean no candidates prints empty state", run: testCLISubprocessTaskCleanNoCandidates),
  .init(name: "cli subprocess task clean yes removes merged task", run: testCLISubprocessTaskCleanYes),
]

func testCLISubprocessHelp() throws {
  try withIntegrationEnvironment { env in
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["help"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected help exit status 0")
    try expect(result.stdout == usageText() + "\n", "expected help snapshot output")
  }
}

func testCLISubprocessHelpFlags() throws {
  try withIntegrationEnvironment { env in
    let short = try runCLI(repoRoot: env.repoRoot, arguments: ["-h"], environment: ProcessInfo.processInfo.environment)
    let long = try runCLI(repoRoot: env.repoRoot, arguments: ["--help"], environment: ProcessInfo.processInfo.environment)
    try expect(short.status == 0 && long.status == 0, "expected help flags to exit zero")
    try expect(short.stdout == usageText() + "\n", "expected -h output to match usage")
    try expect(long.stdout == usageText() + "\n", "expected --help output to match usage")
  }
}

func testCLISubprocessProjectListEmpty() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["project", "list"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected empty project list to succeed")
    try expect(result.stdout.isEmpty, "expected empty project list output")
  }
}

func testCLISubprocessCompletionsInitZsh() throws {
  try withIntegrationEnvironment { env in
    let home = env.root.appendingPathComponent("Home With Spaces", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let envVars = ProcessInfo.processInfo.environment.merging(["HOME": home.path]) { _, new in new }
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["completions", "init", "zsh"], environment: envVars)
    let zshrc = home.appendingPathComponent(".zshrc")
    let contents = try String(contentsOf: zshrc, encoding: .utf8)
    try expect(result.status == 0, "expected completions init exit status 0")
    try expect(contents.contains("# >>> hatch completions >>>"), "expected completions block in zshrc")
    try expect(contents.contains("eval \"$(hatch completions zsh)\""), "expected zsh eval line")
  }
}

func testCLISubprocessCompletionsInitZshIdempotent() throws {
  try withIntegrationEnvironment { env in
    let home = env.root.appendingPathComponent("Home", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let envVars = ProcessInfo.processInfo.environment.merging(["HOME": home.path]) { _, new in new }
    let first = try runCLI(repoRoot: env.repoRoot, arguments: ["completions", "init", "zsh"], environment: envVars)
    let second = try runCLI(repoRoot: env.repoRoot, arguments: ["completions", "init", "zsh"], environment: envVars)
    let zshrc = home.appendingPathComponent(".zshrc")
    let contents = try String(contentsOf: zshrc, encoding: .utf8)
    try expect(first.status == 0 && second.status == 0, "expected repeated completions init to succeed")
    try expect(contents.components(separatedBy: "# >>> hatch completions >>>").count - 1 == 1, "expected single managed block after repeated init")
    try expect(second.stdout.contains("already configured"), "expected idempotent message on second run")
  }
}

func testCLISubprocessProjectCommandWithoutSubcommand() throws {
  try withIntegrationEnvironment { env in
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["project"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected bare project command to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: usage: hatch project <create|list|config> ...", "expected exact project usage error")
  }
}

func testCLISubprocessTaskCommandWithoutSubcommand() throws {
  try withIntegrationEnvironment { env in
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected bare task command to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: usage: hatch task <create|resume|list|clean> ...", "expected exact task usage error")
  }
}

func testCLISubprocessTaskResume() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let refreshed = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "task-a", paths: refreshed.paths, config: env.workspaceConfig)

    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task", "resume", "task-a"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected task resume exit status 0")
    try expect(result.stdout.contains(task.path.path), "expected resumed task path on stdout")
  }
}

func testCLISubprocessTaskResumeNoMatch() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task", "resume", "missing-task"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected missing task resume to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: No task matching missing-task exists in any project", "expected exact missing task stderr")
  }
}

func testCLISubprocessTaskResumeAmbiguity() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "beta", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    _ = try behavior.createTask(project: "alpha", task: "same", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    _ = try behavior.createTask(project: "beta", task: "same", paths: state.paths, config: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task", "resume", "same"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected ambiguous task resume to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: Task name same is ambiguous. Matches: alpha/same, beta/same", "expected exact ambiguity stderr")
  }
}

func testCLISubprocessUnknownCommandFails() throws {
  try withIntegrationEnvironment { env in
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["bogus"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected unknown command non-zero exit")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: unknown command 'bogus'", "expected exact unknown command stderr")
  }
}

func testCLISubprocessProjectAliasWorks() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["p", "create", "alpha"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected project alias create to succeed")
    try expect(FileManager.default.fileExists(atPath: env.workspaceRoot.appendingPathComponent("alpha/.project").path), "expected project alias to create project")
  }
}

func testCLISubprocessTaskAliasWorks() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["t", "create", "alpha", "one"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected task alias create to succeed")
    try expect(FileManager.default.fileExists(atPath: env.workspaceRoot.appendingPathComponent("alpha/one").path), "expected task alias to create task")
  }
}

func testCLISubprocessProjectCreateDuplicateFails() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["project", "create", "alpha"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected duplicate project create to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: \(env.workspaceRoot.appendingPathComponent("alpha").path) already exists", "expected exact duplicate project stderr")
  }
}

func testCLISubprocessProjectCreateWrongArity() throws {
  try withIntegrationEnvironment { env in
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["project", "create"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected wrong-arity project create to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: usage: hatch project create <project-name>", "expected exact project create usage error")
  }
}

func testCLISubprocessTaskCreateMissingProjectFails() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task", "create", "missing", "one"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected missing project task create to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: project \(env.workspaceRoot.appendingPathComponent("missing").path) does not exist", "expected exact missing project stderr")
  }
}

func testCLISubprocessTaskCreateWrongArity() throws {
  try withIntegrationEnvironment { env in
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task", "create", "alpha"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected wrong-arity task create to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: usage: hatch task create <project-name> <task-name>", "expected exact task create usage error")
  }
}

func testCLISubprocessTaskListEmpty() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task", "list"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected empty task list to succeed")
    try expect(result.stdout.isEmpty, "expected empty task list output")
  }
}

func testCLISubprocessTaskListFiltersByProject() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    var state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "beta", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    _ = try behavior.createTask(project: "alpha", task: "one", paths: state.paths, config: env.workspaceConfig)
    state = try behavior.loadAppState()
    _ = try behavior.createTask(project: "beta", task: "two", paths: state.paths, config: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task", "list", "alpha"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected task list filter to succeed")
    try expect(result.stdout.contains("alpha/one"), "expected filtered task in output")
    try expect(!result.stdout.contains("beta/two"), "expected non-filtered task excluded")
  }
}

func testCLISubprocessProjectConfigOpensEditor() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    let project = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["project", "config", "alpha"], environment: ProcessInfo.processInfo.environment)
    let editorLog = try String(contentsOf: env.editorLog, encoding: .utf8)
    let configPath = project.path.appendingPathComponent("hatch.toml").path
    try expect(result.status == 0, "expected project config exit status 0")
    try expect(result.stdout.contains(configPath), "expected config path on stdout")
    try expect(editorLog.contains(configPath), "expected editor to open project config")
  }
}

func testCLISubprocessProjectConfigRecreatesMissingFile() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    let project = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let configFile = project.path.appendingPathComponent("hatch.toml")
    try FileManager.default.removeItem(at: configFile)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["project", "config", "alpha"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected project config recreation to succeed")
    try expect(FileManager.default.fileExists(atPath: configFile.path), "expected project config file to be recreated")
  }
}

func testCLISubprocessProjectConfigMissingProjectFails() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["project", "config", "missing"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected missing project config to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: project missing does not exist", "expected exact missing project config stderr")
  }
}

func testCLISubprocessProjectConfigWrongArity() throws {
  try withIntegrationEnvironment { env in
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["project", "config"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status != 0, "expected wrong-arity project config to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: usage: hatch project config <project-name>", "expected exact project config usage error")
  }
}

func testCLISubprocessCheckout() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let refreshed = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "task-a", paths: refreshed.paths, config: env.workspaceConfig)
    let result = try runCLI(
      repoRoot: env.repoRoot,
      arguments: ["checkout", "web"],
      environment: ProcessInfo.processInfo.environment,
      currentDirectory: task.path
    )
    try expect(result.status == 0, "expected checkout exit status 0")
    let repoPath = task.path.appendingPathComponent("web")
    try expect(FileManager.default.fileExists(atPath: repoPath.appendingPathComponent(".git").path), "expected checked out repo")
  }
}

func testCLISubprocessCheckoutOutsideTaskFails() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let result = try runCLI(
      repoRoot: env.repoRoot,
      arguments: ["checkout", "web"],
      environment: ProcessInfo.processInfo.environment,
      currentDirectory: env.workspaceRoot
    )
    try expect(result.status != 0, "expected checkout outside task to fail")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: must be run from within a task folder", "expected exact checkout outside task stderr")
  }
}

func testCLISubprocessCheckoutFailure() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let refreshed = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "task-a", paths: refreshed.paths, config: WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: [],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [:]
    ))
    let envVars = ProcessInfo.processInfo.environment.merging(["GIT_FAIL_CLONE": "1"]) { _, new in new }
    let result = try runCLI(
      repoRoot: env.repoRoot,
      arguments: ["checkout", "web"],
      environment: envVars,
      currentDirectory: task.path
    )
    try expect(result.status != 0, "expected checkout failure exit")
    try expect(lastNonEmptyLine(in: result.stderr) == "hatch: clone failed", "expected exact clone failure stderr")
  }
}

func testCLISubprocessTaskCleanInteractive() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    let config = WorkspaceConfig(
      defaultOrg: env.workspaceConfig.defaultOrg,
      defaultRepos: ["api"],
      branchTemplate: env.workspaceConfig.branchTemplate,
      editor: env.workspaceConfig.editor,
      hooksInclude: [],
      hooks: [:]
    )
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: config)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: config)
    let refreshed = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "task-a", paths: refreshed.paths, config: config)
    try "merged-branch\n".write(to: task.path.appendingPathComponent("api/.branch"), atomically: true, encoding: .utf8)

    let result = try runCLIViaTTY(
      repoRoot: env.repoRoot,
      arguments: ["task", "clean"],
      environment: ProcessInfo.processInfo.environment,
      standardInput: "\n"
    )
    try expect(result.status == 0, "expected interactive task clean exit status 0")
    try expect(FileManager.default.fileExists(atPath: task.path.path), "expected cancelled interactive clean to keep task")
  }
}

func testCLISubprocessTaskCleanNoCandidates() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task", "clean", "--yes"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected empty task clean to succeed")
    try expect(result.stdout == "No tasks with closed or merged PRs found.\n", "expected exact empty clean output")
  }
}

func testCLISubprocessTaskCleanYes() throws {
  try withIntegrationEnvironment { env in
    let behavior = LiveHatchBehavior()
    _ = try behavior.saveConfiguration(bootstrap: env.bootstrap, workspace: env.workspaceConfig)
    let state = try behavior.loadAppState()
    _ = try behavior.createProject(name: "alpha", paths: state.paths, config: env.workspaceConfig)
    let refreshed = try behavior.loadAppState()
    let task = try behavior.createTask(project: "alpha", task: "task-a", paths: refreshed.paths, config: env.workspaceConfig)
    try "merged-branch\n".write(to: task.path.appendingPathComponent("api/.branch"), atomically: true, encoding: .utf8)

    let result = try runCLI(repoRoot: env.repoRoot, arguments: ["task", "clean", "--yes"], environment: ProcessInfo.processInfo.environment)
    try expect(result.status == 0, "expected task clean exit status 0")
    try expect(!FileManager.default.fileExists(atPath: task.path.path), "expected cleaned task to be trashed")
    try expect(result.stdout.contains("Deleted 1 task(s)."), "expected delete summary")
  }
}
