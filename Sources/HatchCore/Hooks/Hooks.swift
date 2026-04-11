import Foundation

public enum HookName: String, CaseIterable, Codable, Hashable, Sendable {
  case projectPreCreate = "project_pre_create"
  case projectPostCreate = "project_post_create"
  case taskPreCreate = "task_pre_create"
  case taskPostCreate = "task_post_create"
  case taskPreOpen = "task_pre_open"
  case taskPostOpen = "task_post_open"
  case repoPreAdd = "repo_pre_add"
  case repoPostAdd = "repo_post_add"
}

public enum HookErrorPolicy: String, Codable, Sendable {
  case fail
  case warn
  case ignore
}

public struct HookDefinition: Codable, Equatable, Sendable {
  public var command: [String]
  public var onError: HookErrorPolicy

  public init(command: [String], onError: HookErrorPolicy) {
    self.command = command
    self.onError = onError
  }
}

struct HookContext {
  var workspaceRoot: URL
  var configFile: URL
  var cacheDir: URL
  var project: String?
  var projectPath: URL?
  var task: String?
  var taskPath: URL?
  var repoInput: String?
  var repoPath: URL?

  func environment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["HATCH_WORKSPACE_ROOT"] = workspaceRoot.path
    env["HATCH_CONFIG_FILE"] = configFile.path
    env["HATCH_CACHE_DIR"] = cacheDir.path
    if let project {
      env["HATCH_PROJECT"] = project
    }
    if let projectPath {
      env["HATCH_PROJECT_PATH"] = projectPath.path
    }
    if let task {
      env["HATCH_TASK"] = task
    }
    if let taskPath {
      env["HATCH_TASK_PATH"] = taskPath.path
    }
    if let repoInput {
      env["HATCH_REPO_INPUT"] = repoInput
    }
    if let repoPath {
      env["HATCH_REPO_PATH"] = repoPath.path
    }
    return env
  }
}
