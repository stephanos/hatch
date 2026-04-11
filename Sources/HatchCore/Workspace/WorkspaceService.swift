import AppKit
import Foundation

struct WorkspaceService {
  let configStore: ConfigStore
  let runner: ProcessRunner
  let hooks: HookRunner
  private let fileManager = FileManager.default
  private var discovery: WorkspaceDiscoveryService {
    WorkspaceDiscoveryService(configStore: configStore)
  }
  private var pathOpener: WorkspacePathOpener {
    WorkspacePathOpener(runner: runner)
  }
  private var repoService: WorkspaceRepoService {
    WorkspaceRepoService(runner: runner)
  }
  private var taskCreationService: TaskCreationService {
    TaskCreationService(
      configStore: configStore,
      hooks: hooks,
      pathOpener: pathOpener,
      repoService: repoService,
      discovery: discovery,
      addRepo: addRepo
    )
  }

  func loadState() throws -> (AppPaths, BootstrapConfig?, WorkspaceConfig?) {
    let paths = try configStore.paths()
    let bootstrap = try configStore.loadBootstrap()
    let config = try configStore.loadWorkspaceConfig(at: paths)
    return (paths, bootstrap, config)
  }

  func recentProjects(paths: AppPaths) throws -> [String] {
    try discovery.recentProjects(paths: paths)
  }

  func saveConfiguration(bootstrap: BootstrapConfig, workspace: WorkspaceConfig) throws -> (
    AppPaths, WorkspaceConfig
  ) {
    guard !workspace.branchTemplate.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw HatchError.message("Branch template must not be empty.")
    }
    try configStore.saveAll(bootstrap: bootstrap, workspace: workspace)
    let paths = try configStore.paths()
    return (paths, workspace)
  }

  func listProjects(paths: AppPaths) throws -> [ProjectSummary] {
    try discovery.listProjects(paths: paths)
  }

  func listTasks(paths: AppPaths) throws -> [TaskSummary] {
    try discovery.listTasks(paths: paths)
  }

  @discardableResult
  func createProject(
    name: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> ProjectSummary {
    let trimmed = try IdentifierValidator.validate(label: "project name", value: name)
    try fileManager.createDirectory(at: paths.workspaceRoot, withIntermediateDirectories: true)
    let projectDir = paths.workspaceRoot.appendingPathComponent(trimmed)
    guard !fileManager.fileExists(atPath: projectDir.path) else {
      throw HatchError.message("\(projectDir.path) already exists")
    }

    let hookContext = HookContext(
      workspaceRoot: paths.workspaceRoot,
      configFile: paths.workspaceConfigFile,
      cacheDir: paths.cacheDirectory,
      project: trimmed,
      projectPath: projectDir,
      task: nil,
      taskPath: nil,
      repoInput: nil,
      repoPath: nil
    )
    try hooks.run(.projectPreCreate, context: hookContext, config: config)

    try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
    try "".write(
      to: projectDir.appendingPathComponent(".project"), atomically: true, encoding: .utf8)
    try configStore.saveProjectConfig(
      ProjectConfig(defaultRepos: config.defaultRepos, repoBaseBranches: [:]),
      projectDirectory: projectDir
    )

    try hooks.run(.projectPostCreate, context: hookContext, config: config)
    return ProjectSummary(name: trimmed, path: projectDir)
  }

  func previewProjectCreation(
    name: String,
    paths: AppPaths
  ) throws -> ProjectCreationPreview {
    let trimmed = try IdentifierValidator.validate(label: "project name", value: name)
    let projectDir = paths.workspaceRoot.appendingPathComponent(trimmed)

    return ProjectCreationPreview(
      project: trimmed,
      projectDirectory: projectDir,
      configFile: projectDir.appendingPathComponent(ConfigPaths.projectConfigFilename)
    )
  }

  @discardableResult
  func createTask(
    project: String,
    task: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> TaskSummary {
    let preview = try previewTaskCreation(
      project: project, task: task, paths: paths, config: config)
    return try taskCreationService.createTask(
      project: project,
      task: task,
      paths: paths,
      config: config,
      preview: preview
    )
  }

  func previewTaskCreation(
    project: String,
    task: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> TaskCreationPreview {
    let validatedTask = try IdentifierValidator.validate(label: "task name", value: task)
    let projectDir = paths.workspaceRoot.appendingPathComponent(project)
    guard fileManager.fileExists(atPath: projectDir.appendingPathComponent(".project").path) else {
      throw HatchError.message("project \(projectDir.path) does not exist")
    }

    let taskDir = projectDir.appendingPathComponent(validatedTask)
    let projectConfig = try configStore.loadProjectConfig(projectDirectory: projectDir) ?? .default
    let repoInputs =
      projectConfig.defaultRepos.isEmpty ? config.defaultRepos : projectConfig.defaultRepos
    let repos = try repoInputs.map { repoInput in
      let repoSpec = try repoService.resolveRepoSpec(
        repoInput: repoInput,
        defaultOrg: config.defaultOrg
      )
      return RepoCreationPreview(
        name: repoSpec.repo,
        destination: taskDir.appendingPathComponent(repoSpec.repo),
        cloneURL: repoSpec.cloneURL,
        branchName: repoService.renderTemplate(
          config.branchTemplate,
          values: [
            "user": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
            "project": project,
            "task": validatedTask,
          ]
        ),
        baseBranch: projectConfig.repoBaseBranches[repoSpec.repo]
      )
    }

    return TaskCreationPreview(
      project: project,
      task: validatedTask,
      taskDirectory: taskDir,
      repos: repos
    )
  }

  func openTask(_ task: TaskSummary, paths: AppPaths, config: WorkspaceConfig) throws {
    let context = HookContext(
      workspaceRoot: paths.workspaceRoot,
      configFile: paths.workspaceConfigFile,
      cacheDir: paths.cacheDirectory,
      project: task.project,
      projectPath: paths.workspaceRoot.appendingPathComponent(task.project),
      task: task.task,
      taskPath: task.path,
      repoInput: nil,
      repoPath: nil
    )
    try hooks.run(.taskPreOpen, context: context, config: config)
    try pathOpener.openTaskPath(task.path, editor: config.editor)
    try discovery.markProjectAsRecent(task.project, paths: paths)
    try hooks.run(.taskPostOpen, context: context, config: config)
  }

  func openProjectConfig(_ project: ProjectSummary, editor: String?) throws {
    if try configStore.loadProjectConfig(projectDirectory: project.path) == nil {
      try configStore.saveProjectConfig(.default, projectDirectory: project.path)
    }
    try pathOpener.openPath(project.path.appendingPathComponent("hatch.toml"), editor: editor)
  }

  func saveProjectConfig(_ config: ProjectConfig, project: ProjectSummary) throws {
    try configStore.saveProjectConfig(config, projectDirectory: project.path)
  }

  func projectConfig(for project: ProjectSummary) throws -> ProjectConfig {
    try configStore.loadProjectConfig(projectDirectory: project.path) ?? .default
  }

  func addRepo(
    repoInput: String,
    taskDirectory: URL,
    projectConfig: ProjectConfig,
    paths: AppPaths,
    config: WorkspaceConfig,
    force: Bool
  ) throws {
    let resolvedTask = try discovery.resolveTaskContext(from: taskDirectory)
    let repoSpec = try repoService.resolveRepoSpec(
      repoInput: repoInput, defaultOrg: config.defaultOrg)
    let repoPath = resolvedTask.path.appendingPathComponent(repoSpec.repo)

    if fileManager.fileExists(atPath: repoPath.path) {
      if force {
        try fileManager.removeItem(at: repoPath)
      } else {
        throw HatchError.message("\(repoPath.path) already exists")
      }
    }

    let context = HookContext(
      workspaceRoot: paths.workspaceRoot,
      configFile: paths.workspaceConfigFile,
      cacheDir: paths.cacheDirectory,
      project: resolvedTask.project,
      projectPath: paths.workspaceRoot.appendingPathComponent(resolvedTask.project),
      task: resolvedTask.task,
      taskPath: resolvedTask.path,
      repoInput: repoInput,
      repoPath: nil
    )
    try hooks.run(.repoPreAdd, context: context, config: config)

    try runner.run("git", arguments: ["clone", repoSpec.cloneURL, repoPath.path])
    do {
      let branchName = repoService.renderTemplate(
        config.branchTemplate,
        values: [
          "user": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
          "project": resolvedTask.project,
          "task": resolvedTask.task,
        ]
      )
      let baseBranch = projectConfig.repoBaseBranches[repoSpec.repo]
      try repoService.checkoutTaskBranch(at: repoPath, branch: branchName, baseBranch: baseBranch)

      try hooks.run(
        .repoPostAdd,
        context: HookContext(
          workspaceRoot: paths.workspaceRoot,
          configFile: paths.workspaceConfigFile,
          cacheDir: paths.cacheDirectory,
          project: resolvedTask.project,
          projectPath: paths.workspaceRoot.appendingPathComponent(resolvedTask.project),
          task: resolvedTask.task,
          taskPath: resolvedTask.path,
          repoInput: repoInput,
          repoPath: repoPath
        ),
        config: config
      )
    } catch {
      if fileManager.fileExists(atPath: repoPath.path) {
        try? fileManager.removeItem(at: repoPath)
      }
      throw error
    }
  }

}
