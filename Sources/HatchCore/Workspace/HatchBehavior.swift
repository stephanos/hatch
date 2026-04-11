import Foundation

public struct LoadedAppState {
  public let paths: AppPaths
  public let bootstrap: BootstrapConfig?
  public let workspaceConfig: WorkspaceConfig?
  public let projects: [ProjectSummary]
  public let tasks: [TaskSummary]
  public let recentProjects: [String]

  public init(
    paths: AppPaths,
    bootstrap: BootstrapConfig?,
    workspaceConfig: WorkspaceConfig?,
    projects: [ProjectSummary],
    tasks: [TaskSummary],
    recentProjects: [String]
  ) {
    self.paths = paths
    self.bootstrap = bootstrap
    self.workspaceConfig = workspaceConfig
    self.projects = projects
    self.tasks = tasks
    self.recentProjects = recentProjects
  }
}

public protocol HatchBehavior {
  func loadAppState() throws -> LoadedAppState
  func saveConfiguration(
    bootstrap: BootstrapConfig,
    workspace: WorkspaceConfig
  ) throws -> LoadedAppState
  func createProject(
    name: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> ProjectSummary
  func previewProjectCreation(
    name: String,
    paths: AppPaths
  ) throws -> ProjectCreationPreview
  func createTask(
    project: String,
    task: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> TaskSummary
  func previewTaskCreation(
    project: String,
    task: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> TaskCreationPreview
  func openTask(_ task: TaskSummary, paths: AppPaths, config: WorkspaceConfig) throws
  func openProjectConfig(_ project: ProjectSummary, editor: String?) throws
  func loadProjectConfig(for project: ProjectSummary) throws -> ProjectConfig
  func saveProjectConfig(_ config: ProjectConfig, project: ProjectSummary) throws
  func addRepo(
    repoInput: String,
    taskDirectory: URL,
    projectConfig: ProjectConfig,
    paths: AppPaths,
    config: WorkspaceConfig,
    force: Bool
  ) throws
}

public struct LiveHatchBehavior: HatchBehavior {
  private let workspaceService: WorkspaceService
  private let cliInstaller = CLIInstaller()

  public init(
    configStore: ConfigStore = ConfigStore(),
    runner: ProcessRunner = ProcessRunner(),
    hookFailureReporter: (any HookFailureReporter)? = nil
  ) {
    workspaceService = WorkspaceService(
      configStore: configStore,
      runner: runner,
      hooks: HookRunner(runner: runner, reporter: hookFailureReporter)
    )
  }

  public func loadAppState() throws -> LoadedAppState {
    let (paths, bootstrap, workspaceConfig) = try workspaceService.loadState()
    let projects = try workspaceService.listProjects(paths: paths)
    let tasks = try workspaceService.listTasks(paths: paths)
    let recentProjects = try workspaceService.recentProjects(paths: paths)
    return LoadedAppState(
      paths: paths,
      bootstrap: bootstrap,
      workspaceConfig: workspaceConfig,
      projects: projects,
      tasks: tasks,
      recentProjects: recentProjects
    )
  }

  public func saveConfiguration(
    bootstrap: BootstrapConfig,
    workspace: WorkspaceConfig
  ) throws -> LoadedAppState {
    _ = try workspaceService.saveConfiguration(bootstrap: bootstrap, workspace: workspace)
    try cliInstaller.install(using: bootstrap)
    return try loadAppState()
  }

  public func createProject(
    name: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> ProjectSummary {
    try workspaceService.createProject(name: name, paths: paths, config: config)
  }

  public func previewProjectCreation(
    name: String,
    paths: AppPaths
  ) throws -> ProjectCreationPreview {
    try workspaceService.previewProjectCreation(name: name, paths: paths)
  }

  public func createTask(
    project: String,
    task: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> TaskSummary {
    try workspaceService.createTask(project: project, task: task, paths: paths, config: config)
  }

  public func previewTaskCreation(
    project: String,
    task: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> TaskCreationPreview {
    try workspaceService.previewTaskCreation(
      project: project,
      task: task,
      paths: paths,
      config: config
    )
  }

  public func openTask(_ task: TaskSummary, paths: AppPaths, config: WorkspaceConfig) throws {
    try workspaceService.openTask(task, paths: paths, config: config)
  }

  public func openProjectConfig(_ project: ProjectSummary, editor: String?) throws {
    try workspaceService.openProjectConfig(project, editor: editor)
  }

  public func loadProjectConfig(for project: ProjectSummary) throws -> ProjectConfig {
    try workspaceService.projectConfig(for: project)
  }

  public func saveProjectConfig(_ config: ProjectConfig, project: ProjectSummary) throws {
    try workspaceService.saveProjectConfig(config, project: project)
  }

  public func addRepo(
    repoInput: String,
    taskDirectory: URL,
    projectConfig: ProjectConfig,
    paths: AppPaths,
    config: WorkspaceConfig,
    force: Bool
  ) throws {
    try workspaceService.addRepo(
      repoInput: repoInput,
      taskDirectory: taskDirectory,
      projectConfig: projectConfig,
      paths: paths,
      config: config,
      force: force
    )
  }
}
