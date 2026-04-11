import Foundation

typealias AddRepoAction = (
  _ repoInput: String,
  _ taskDirectory: URL,
  _ projectConfig: ProjectConfig,
  _ paths: AppPaths,
  _ config: WorkspaceConfig,
  _ force: Bool
) throws -> Void

struct TaskCreationService {
  let configStore: ConfigStore
  let hooks: HookRunner
  let pathOpener: WorkspacePathOpener
  let repoService: WorkspaceRepoService
  let discovery: WorkspaceDiscoveryService
  let addRepo: AddRepoAction

  private let fileManager = FileManager.default

  @discardableResult
  func createTask(
    project: String,
    task: String,
    paths: AppPaths,
    config: WorkspaceConfig,
    preview: TaskCreationPreview
  ) throws -> TaskSummary {
    let validatedTask = preview.task
    let projectDir = paths.workspaceRoot.appendingPathComponent(project)
    let taskDir = preview.taskDirectory
    guard !fileManager.fileExists(atPath: taskDir.path) else {
      throw HatchError.message("\(taskDir.path) already exists")
    }

    let hookContext = HookContext(
      workspaceRoot: paths.workspaceRoot,
      configFile: paths.workspaceConfigFile,
      cacheDir: paths.cacheDirectory,
      project: project,
      projectPath: projectDir,
      task: validatedTask,
      taskPath: taskDir,
      repoInput: nil,
      repoPath: nil
    )
    try hooks.run(.taskPreCreate, context: hookContext, config: config)

    try fileManager.createDirectory(at: taskDir, withIntermediateDirectories: true)
    do {
      try hooks.run(.taskPostCreate, context: hookContext, config: config)

      let projectConfig =
        try configStore.loadProjectConfig(projectDirectory: projectDir) ?? .default
      for repo in preview.repos {
        try addRepo(repo.cloneURL, taskDir, projectConfig, paths, config, false)
      }

      try pathOpener.openTaskPath(taskDir, editor: config.editor)
      try discovery.markProjectAsRecent(project, paths: paths)
      try hooks.run(.taskPostOpen, context: hookContext, config: config)
      return TaskSummary(project: project, task: validatedTask, path: taskDir)
    } catch {
      if fileManager.fileExists(atPath: taskDir.path) {
        try? fileManager.removeItem(at: taskDir)
      }
      throw error
    }
  }
}
