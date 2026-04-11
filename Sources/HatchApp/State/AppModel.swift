import Combine
import Foundation
import HatchCore
import HatchSupport

@MainActor
package final class AppModel: ObservableObject {
  @Published package var paths: AppPaths?
  @Published package var bootstrap: BootstrapConfig?
  @Published package var workspaceConfig: WorkspaceConfig?
  @Published package var projects: [ProjectSummary] = []
  @Published package var tasks: [TaskSummary] = []
  @Published package var recentProjects: [String] = []
  @Published package var selectedProject: ProjectSummary?
  @Published package var selectedTask: TaskSummary?
  @Published package var selectedProjectConfig: ProjectConfig = .default
  @Published package var searchText = ""
  @Published package var createProjectName = ""
  @Published package var createTaskName = ""
  @Published package var repoToAdd = ""
  @Published package var alertError: HatchError?

  private let behavior: HatchBehavior
  private let runtimeMode = HatchRuntimeMode.current()

  package init(behavior: HatchBehavior = LiveHatchBehavior()) {
    self.behavior = behavior
  }

  package var isConfigured: Bool {
    bootstrap != nil && workspaceConfig != nil
  }

  package func reload() {
    do {
      let state = try behavior.loadAppState()
      applyLoadedState(state)
      alertError = nil
    } catch {
      if runtimeMode.suppressesLoadErrors {
        applyEmptyState()
        alertError = nil
      } else {
        alertError = .message(error.localizedDescription)
      }
    }
  }

  package func saveConfiguration(bootstrap: BootstrapConfig, workspace: WorkspaceConfig) {
    performOperation {
      let state = try behavior.saveConfiguration(bootstrap: bootstrap, workspace: workspace)
      applyLoadedState(state)
    }
  }

  package func createProject() {
    createProject(named: createProjectName)
  }

  package func createProject(named name: String) {
    withWorkspaceContext { paths, workspaceConfig in
      let project = try behavior.createProject(
        name: name,
        paths: paths,
        config: workspaceConfig
      )
      let state = try behavior.loadAppState()
      applyLoadedState(state)
      applyProjectCreation(project)
    }
  }

  package func previewProjectCreation(name: String) -> ProjectCreationPreview? {
    guard let paths else { return nil }
    do {
      return try behavior.previewProjectCreation(name: name, paths: paths)
    } catch {
      return nil
    }
  }

  package func createTask() {
    guard let project = selectedProject else { return }
    createTask(projectName: project.name, taskName: createTaskName)
  }

  package func createTask(projectName: String, taskName: String) {
    withWorkspaceContext { paths, workspaceConfig in
      let task = try behavior.createTask(
        project: projectName,
        task: taskName,
        paths: paths,
        config: workspaceConfig
      )
      let state = try behavior.loadAppState()
      applyLoadedState(state)
      applyTaskCreation(task, projectName: projectName)
    }
  }

  package func previewTaskCreation(projectName: String, taskName: String) -> TaskCreationPreview? {
    guard let paths, let workspaceConfig else { return nil }
    do {
      return try behavior.previewTaskCreation(
        project: projectName,
        task: taskName,
        paths: paths,
        config: workspaceConfig
      )
    } catch {
      return nil
    }
  }

  package func openSelectedTask() {
    guard let task = selectedTask else { return }
    openTask(task)
  }

  package func openTask(_ task: TaskSummary) {
    withWorkspaceContext { paths, workspaceConfig in
      try behavior.openTask(task, paths: paths, config: workspaceConfig)
      moveProjectToRecentFront(task.project)
      selectedProject = projects.first(where: { $0.name == task.project })
      selectedTask = task
    }
  }

  package func openSelectedProjectConfig() {
    guard let project = selectedProject else { return }
    openProjectConfig(project)
  }

  package func openProjectConfig(_ project: ProjectSummary) {
    guard let workspaceConfig else { return }
    performOperation {
      try behavior.openProjectConfig(project, editor: workspaceConfig.editor)
      selectedProject = project
    }
  }

  package func addRepoToSelectedTask() {
    guard
      let selectedTask,
      let paths,
      let workspaceConfig,
      let project = selectedProject
    else { return }
    performOperation {
      let projectConfig = try behavior.loadProjectConfig(for: project)
      try behavior.addRepo(
        repoInput: repoToAdd,
        taskDirectory: selectedTask.path,
        projectConfig: projectConfig,
        paths: paths,
        config: workspaceConfig,
        force: false
      )
      applyRepoAdded()
    }
  }

  package func refreshSelectedProjectConfig() throws {
    if let selectedProject {
      selectedProjectConfig = try behavior.loadProjectConfig(for: selectedProject)
    } else {
      selectedProjectConfig = .default
    }
  }

  package func saveSelectedProjectConfig() {
    guard let selectedProject else { return }
    performOperation {
      try behavior.saveProjectConfig(selectedProjectConfig, project: selectedProject)
      let state = try behavior.loadAppState()
      applyLoadedState(state)
    }
  }

  package var filteredTasks: [TaskSummary] {
    guard !searchText.isEmpty else { return tasks }
    let matchingProjects = Set(
      tasks
        .map(\.project)
        .filter { $0.localizedCaseInsensitiveContains(searchText) }
    )

    return tasks.filter {
      matchingProjects.contains($0.project)
        || "\($0.project)/\($0.task)".localizedCaseInsensitiveContains(searchText)
        || $0.task.localizedCaseInsensitiveContains(searchText)
    }
  }

  private func applyLoadedState(_ state: LoadedAppState) {
    paths = state.paths
    bootstrap = state.bootstrap
    workspaceConfig = state.workspaceConfig
    projects = state.projects
    tasks = state.tasks
    recentProjects = state.recentProjects

    if let selectedProject {
      self.selectedProject = projects.first(where: { $0.id == selectedProject.id })
      try? refreshSelectedProjectConfig()
    }
    if let selectedTask {
      self.selectedTask = tasks.first(where: { $0.id == selectedTask.id })
    }
  }

  private func withWorkspaceContext(
    _ action: (AppPaths, WorkspaceConfig) throws -> Void
  ) {
    guard let paths, let workspaceConfig else { return }
    performOperation {
      try action(paths, workspaceConfig)
    }
  }

  private func performOperation(_ action: () throws -> Void) {
    do {
      try action()
    } catch {
      alertError = .message(error.localizedDescription)
    }
  }

  private func applyEmptyState() {
    paths = nil
    bootstrap = nil
    workspaceConfig = nil
    projects = []
    tasks = []
    recentProjects = []
    selectedProject = nil
    selectedTask = nil
    selectedProjectConfig = .default
  }

  private func applyProjectCreation(_ project: ProjectSummary) {
    createProjectName = ""
    selectedProject = project
    try? refreshSelectedProjectConfig()
  }

  private func applyTaskCreation(_ task: TaskSummary, projectName: String) {
    createTaskName = ""
    selectedProject = projects.first(where: { $0.name == projectName })
    selectedTask = task
  }

  private func applyRepoAdded() {
    repoToAdd = ""
  }

  private func moveProjectToRecentFront(_ project: String) {
    recentProjects.removeAll { $0 == project }
    recentProjects.insert(project, at: 0)
  }
}
