import Foundation
import HatchAppState
import HatchCore

let appModelTests: [TestCase] = [
  .init(name: "app model save configuration updates state", run: testAppModelSaveConfigurationUpdatesState),
  .init(name: "app model create project surfaces errors", run: testAppModelCreateProjectSurfacesErrors),
  .init(name: "app model create task reloads and updates selection", run: testAppModelCreateTaskReloadsAndUpdatesSelection),
  .init(name: "app model open task reorders recents", run: testAppModelOpenTaskReordersRecents),
  .init(name: "app model filtered tasks matches search", run: testAppModelFilteredTasksMatchesSearch),
  .init(name: "app model filtered tasks includes project matches", run: testAppModelFilteredTasksIncludesProjectMatches),
  .init(name: "app model preview project creation returns plan", run: testAppModelPreviewProjectCreationReturnsPlan),
  .init(name: "app model preview task creation returns plan", run: testAppModelPreviewTaskCreationReturnsPlan),
  .init(name: "app model add repo clears input and records request", run: testAppModelAddRepoClearsInputAndRecordsRequest),
  .init(name: "app model save selected project config reloads state", run: testAppModelSaveSelectedProjectConfigReloadsState),
  .init(name: "app model reload preserves selected project and task", run: testAppModelReloadPreservesSelection),
]

func testAppModelSaveConfigurationUpdatesState() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model"))
  let bootstrap = BootstrapConfig(
    workspaceRoot: paths.workspaceRoot.path,
    cliInstallPath: "~/.local/bin"
  )
  let workspace = WorkspaceConfig.default
  let project = ProjectSummary(
    name: "alpha",
    path: paths.workspaceRoot.appendingPathComponent("alpha")
  )
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: bootstrap,
      workspaceConfig: workspace,
      projects: [project],
      tasks: [],
      recentProjects: []
    )
  )

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.saveConfiguration(bootstrap: bootstrap, workspace: workspace)
    try expect(model.isConfigured, "expected configured app model")
    try expect(model.bootstrap == bootstrap, "expected bootstrap to be stored")
    try expect(model.workspaceConfig == workspace, "expected workspace config to be stored")
    try expect(model.projects == [project], "expected projects to load")
  }
}

func testAppModelCreateProjectSurfacesErrors() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-errors"))
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin"),
      workspaceConfig: .default,
      projects: [],
      tasks: [],
      recentProjects: []
    )
  )
  behavior.createProjectError = HatchError.message("boom")

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    model.createProject(named: "alpha")
    try expect(model.alertError?.localizedDescription == "boom", "expected app model to surface create project error")
  }
}

func testAppModelCreateTaskReloadsAndUpdatesSelection() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-create-task"))
  let alpha = ProjectSummary(name: "alpha", path: paths.workspaceRoot.appendingPathComponent("alpha"))
  let createdTask = TaskSummary(project: "alpha", task: "one", path: alpha.path.appendingPathComponent("one"))
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin"),
      workspaceConfig: .default,
      projects: [alpha],
      tasks: [],
      recentProjects: []
    )
  )
  behavior.taskToCreate = createdTask

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    model.createTaskName = "one"
    model.createTask(projectName: "alpha", taskName: "one")
    try expect(model.tasks == [createdTask], "expected reload to publish created task")
    try expect(model.selectedProject == alpha, "expected selected project to match created task")
    try expect(model.selectedTask == createdTask, "expected selected task to match created task")
    try expect(model.createTaskName.isEmpty, "expected task name field to reset")
  }
}

func testAppModelOpenTaskReordersRecents() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-open"))
  let workspace = WorkspaceConfig.default
  let bootstrap = BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin")
  let alpha = ProjectSummary(name: "alpha", path: paths.workspaceRoot.appendingPathComponent("alpha"))
  let beta = ProjectSummary(name: "beta", path: paths.workspaceRoot.appendingPathComponent("beta"))
  let task = TaskSummary(project: "alpha", task: "one", path: alpha.path.appendingPathComponent("one"))
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: bootstrap,
      workspaceConfig: workspace,
      projects: [alpha, beta],
      tasks: [task],
      recentProjects: ["beta", "alpha"]
    )
  )

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    model.openTask(task)
    try expect(model.recentProjects == ["alpha", "beta"], "expected open task to move project to front")
    try expect(model.selectedProject == alpha, "expected selected project to track opened task")
    try expect(model.selectedTask == task, "expected selected task to track opened task")
  }
}

func testAppModelFilteredTasksMatchesSearch() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-filter"))
  let alpha = ProjectSummary(name: "alpha", path: paths.workspaceRoot.appendingPathComponent("alpha"))
  let beta = ProjectSummary(name: "beta", path: paths.workspaceRoot.appendingPathComponent("beta"))
  let tasks = [
    TaskSummary(project: "alpha", task: "api-refactor", path: alpha.path.appendingPathComponent("api-refactor")),
    TaskSummary(project: "beta", task: "docs", path: beta.path.appendingPathComponent("docs")),
  ]
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin"),
      workspaceConfig: .default,
      projects: [alpha, beta],
      tasks: tasks,
      recentProjects: []
    )
  )

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    model.searchText = "alpha/api"
    try expect(model.filteredTasks == [tasks[0]], "expected filtered tasks to match search text")
  }
}

func testAppModelFilteredTasksIncludesProjectMatches() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-project-filter"))
  let alpha = ProjectSummary(name: "alpha", path: paths.workspaceRoot.appendingPathComponent("alpha"))
  let beta = ProjectSummary(name: "beta", path: paths.workspaceRoot.appendingPathComponent("beta"))
  let tasks = [
    TaskSummary(project: "alpha", task: "api-refactor", path: alpha.path.appendingPathComponent("api-refactor")),
    TaskSummary(project: "alpha", task: "design-system", path: alpha.path.appendingPathComponent("design-system")),
    TaskSummary(project: "beta", task: "docs", path: beta.path.appendingPathComponent("docs")),
  ]
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin"),
      workspaceConfig: .default,
      projects: [alpha, beta],
      tasks: tasks,
      recentProjects: []
    )
  )

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    model.searchText = "alp"
    try expect(
      model.filteredTasks == [tasks[0], tasks[1]],
      "expected project-name matches to include all tasks in the matching project"
    )
  }
}

func testAppModelPreviewProjectCreationReturnsPlan() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-project-preview"))
  let preview = ProjectCreationPreview(
    project: "alpha",
    projectDirectory: paths.workspaceRoot.appendingPathComponent("alpha"),
    configFile: paths.workspaceRoot.appendingPathComponent("alpha/hatch.toml")
  )
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin"),
      workspaceConfig: .default,
      projects: [],
      tasks: [],
      recentProjects: []
    )
  )
  behavior.previewProjectCreationResult = preview

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    try expect(model.previewProjectCreation(name: "alpha") == preview, "expected project preview to round-trip through app model")
  }
}

func testAppModelPreviewTaskCreationReturnsPlan() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-preview"))
  let preview = TaskCreationPreview(
    project: "alpha",
    task: "one",
    taskDirectory: paths.workspaceRoot.appendingPathComponent("alpha/one"),
    repos: [
      RepoCreationPreview(
        name: "api",
        destination: paths.workspaceRoot.appendingPathComponent("alpha/one/api"),
        cloneURL: "https://github.com/acme/api.git",
        branchName: "user/one",
        baseBranch: "develop"
      )
    ]
  )
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin"),
      workspaceConfig: .default,
      projects: [ProjectSummary(name: "alpha", path: paths.workspaceRoot.appendingPathComponent("alpha"))],
      tasks: [],
      recentProjects: []
    )
  )
  behavior.previewTaskCreationResult = preview

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    try expect(model.previewTaskCreation(projectName: "alpha", taskName: "one") == preview, "expected task preview to round-trip through app model")
  }
}

func testAppModelAddRepoClearsInputAndRecordsRequest() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-add-repo"))
  let alpha = ProjectSummary(name: "alpha", path: paths.workspaceRoot.appendingPathComponent("alpha"))
  let task = TaskSummary(project: "alpha", task: "one", path: alpha.path.appendingPathComponent("one"))
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin"),
      workspaceConfig: .default,
      projects: [alpha],
      tasks: [task],
      recentProjects: []
    )
  )
  behavior.projectConfigs["alpha"] = ProjectConfig(defaultRepos: ["api"], repoBaseBranches: [:])

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    model.selectedProject = alpha
    model.selectedTask = task
    model.repoToAdd = "web"
    model.addRepoToSelectedTask()
    try expect(model.repoToAdd.isEmpty, "expected repo input to clear after add")
    try expect(behavior.lastAddedRepoInput == "web", "expected repo add request to be recorded")
    try expect(behavior.lastAddedRepoTaskDirectory == task.path, "expected repo add task directory")
  }
}

func testAppModelSaveSelectedProjectConfigReloadsState() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-save-project-config"))
  let alpha = ProjectSummary(name: "alpha", path: paths.workspaceRoot.appendingPathComponent("alpha"))
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin"),
      workspaceConfig: .default,
      projects: [alpha],
      tasks: [],
      recentProjects: []
    )
  )

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    model.selectedProject = alpha
    model.selectedProjectConfig = ProjectConfig(defaultRepos: ["api"], repoBaseBranches: ["api": "develop"])
    model.saveSelectedProjectConfig()
    try expect(behavior.savedProjectConfigs["alpha"] == model.selectedProjectConfig, "expected project config to be persisted")
    try expect(behavior.loadAppStateCallCount > 1, "expected save project config to reload state")
  }
}

func testAppModelReloadPreservesSelection() throws {
  let paths = sampleAppPaths(root: URL(fileURLWithPath: "/tmp/hatch-app-model-reload"))
  let alpha = ProjectSummary(name: "alpha", path: paths.workspaceRoot.appendingPathComponent("alpha"))
  let task = TaskSummary(project: "alpha", task: "one", path: alpha.path.appendingPathComponent("one"))
  let behavior = FakeHatchBehavior(
    state: LoadedAppState(
      paths: paths,
      bootstrap: BootstrapConfig(workspaceRoot: paths.workspaceRoot.path, cliInstallPath: "~/.local/bin"),
      workspaceConfig: .default,
      projects: [alpha],
      tasks: [task],
      recentProjects: []
    )
  )
  behavior.projectConfigs["alpha"] = ProjectConfig(defaultRepos: ["api"], repoBaseBranches: [:])

  try onMainActor {
    let model = AppModel(behavior: behavior)
    model.reload()
    model.selectedProject = alpha
    model.selectedTask = task
    model.reload()
    try expect(model.selectedProject == alpha, "expected reload to preserve selected project")
    try expect(model.selectedTask == task, "expected reload to preserve selected task")
    try expect(model.selectedProjectConfig.defaultRepos == ["api"], "expected reload to refresh selected project config")
  }
}

private func sampleAppPaths(root: URL) -> AppPaths {
  AppPaths(
    bootstrapFile: root.appendingPathComponent("config.toml"),
    workspaceRoot: root.appendingPathComponent("Workspace"),
    hatchRoot: root.appendingPathComponent("Workspace/.hatch"),
    workspaceConfigFile: root.appendingPathComponent("Workspace/.hatch/config.toml"),
    stateDirectory: root.appendingPathComponent("Workspace/.hatch/state"),
    cacheDirectory: root.appendingPathComponent("Workspace/.hatch/cache")
  )
}

private final class FakeHatchBehavior: HatchBehavior, @unchecked Sendable {
  var state: LoadedAppState
  var createProjectError: Error?
  var taskToCreate: TaskSummary?
  var previewProjectCreationResult: ProjectCreationPreview?
  var previewTaskCreationResult: TaskCreationPreview?
  var projectConfigs: [String: ProjectConfig] = [:]
  var savedProjectConfigs: [String: ProjectConfig] = [:]
  var lastAddedRepoInput: String?
  var lastAddedRepoTaskDirectory: URL?
  var loadAppStateCallCount = 0

  init(state: LoadedAppState) {
    self.state = state
  }

  func loadAppState() throws -> LoadedAppState {
    loadAppStateCallCount += 1
    return state
  }

  func saveConfiguration(
    bootstrap: BootstrapConfig,
    workspace: WorkspaceConfig
  ) throws -> LoadedAppState {
    state = LoadedAppState(
      paths: state.paths,
      bootstrap: bootstrap,
      workspaceConfig: workspace,
      projects: state.projects,
      tasks: state.tasks,
      recentProjects: state.recentProjects
    )
    return state
  }

  func createProject(
    name: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> ProjectSummary {
    if let createProjectError { throw createProjectError }
    let project = ProjectSummary(name: name, path: paths.workspaceRoot.appendingPathComponent(name))
    state = LoadedAppState(
      paths: state.paths,
      bootstrap: state.bootstrap,
      workspaceConfig: state.workspaceConfig,
      projects: state.projects + [project],
      tasks: state.tasks,
      recentProjects: state.recentProjects
    )
    return project
  }

  func previewProjectCreation(
    name: String,
    paths: AppPaths
  ) throws -> ProjectCreationPreview {
    if let previewProjectCreationResult {
      return previewProjectCreationResult
    }
    return ProjectCreationPreview(
      project: name,
      projectDirectory: paths.workspaceRoot.appendingPathComponent(name),
      configFile: paths.workspaceRoot.appendingPathComponent(name).appendingPathComponent("hatch.toml")
    )
  }

  func createTask(
    project: String,
    task: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> TaskSummary {
    let summary =
      taskToCreate
      ?? TaskSummary(
        project: project,
        task: task,
        path: paths.workspaceRoot.appendingPathComponent(project).appendingPathComponent(task)
      )
    state = LoadedAppState(
      paths: state.paths,
      bootstrap: state.bootstrap,
      workspaceConfig: state.workspaceConfig,
      projects: state.projects,
      tasks: state.tasks + [summary],
      recentProjects: state.recentProjects
    )
    return summary
  }

  func previewTaskCreation(
    project: String,
    task: String,
    paths: AppPaths,
    config: WorkspaceConfig
  ) throws -> TaskCreationPreview {
    if let previewTaskCreationResult {
      return previewTaskCreationResult
    }
    return TaskCreationPreview(
      project: project,
      task: task,
      taskDirectory: paths.workspaceRoot.appendingPathComponent(project).appendingPathComponent(task),
      repos: []
    )
  }

  func openTask(_ task: TaskSummary, paths: AppPaths, config: WorkspaceConfig) throws {}

  func openProjectConfig(_ project: ProjectSummary, editor: String?) throws {}

  func loadProjectConfig(for project: ProjectSummary) throws -> ProjectConfig {
    projectConfigs[project.name] ?? .default
  }

  func saveProjectConfig(_ config: ProjectConfig, project: ProjectSummary) throws {
    savedProjectConfigs[project.name] = config
    projectConfigs[project.name] = config
  }

  func addRepo(
    repoInput: String,
    taskDirectory: URL,
    projectConfig: ProjectConfig,
    paths: AppPaths,
    config: WorkspaceConfig,
    force: Bool
  ) throws {
    lastAddedRepoInput = repoInput
    lastAddedRepoTaskDirectory = taskDirectory
  }
}
