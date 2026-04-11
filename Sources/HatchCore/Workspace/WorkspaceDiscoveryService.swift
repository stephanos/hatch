import Foundation

struct WorkspaceDiscoveryService {
  let configStore: ConfigStore
  private let fileManager = FileManager.default

  func recentProjects(paths: AppPaths) throws -> [String] {
    try configStore.loadRecentProjects(from: paths)
  }

  func markProjectAsRecent(_ project: String, paths: AppPaths) throws {
    let existing = try configStore.loadRecentProjects(from: paths)
    var updated = existing.filter { $0 != project }
    updated.insert(project, at: 0)
    try configStore.saveRecentProjects(updated, paths: paths)
  }

  func listProjects(paths: AppPaths) throws -> [ProjectSummary] {
    guard fileManager.fileExists(atPath: paths.workspaceRoot.path) else { return [] }
    return try fileManager.contentsOfDirectory(
      at: paths.workspaceRoot, includingPropertiesForKeys: nil
    )
    .filter { url in
      var isDir: ObjCBool = false
      return fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        && isDir.boolValue
        && fileManager.fileExists(atPath: url.appendingPathComponent(".project").path)
        && !["old", "skills", ".hatch"].contains(url.lastPathComponent)
    }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .map { ProjectSummary(name: $0.lastPathComponent, path: $0) }
  }

  func listTasks(paths: AppPaths) throws -> [TaskSummary] {
    var tasks: [TaskSummary] = []
    for project in try listProjects(paths: paths) {
      let children = try fileManager.contentsOfDirectory(
        at: project.path, includingPropertiesForKeys: nil)
      for child in children where child.hasDirectoryPath && child.lastPathComponent != ".hatch" {
        if child.lastPathComponent == ".project" || child.lastPathComponent == "hatch.toml" {
          continue
        }
        tasks.append(TaskSummary(project: project.name, task: child.lastPathComponent, path: child))
      }
    }
    return tasks.sorted { ($0.project, $0.task) < ($1.project, $1.task) }
  }

  func resolveTaskContext(from url: URL) throws -> TaskSummary {
    let canonical = url.resolvingSymlinksInPath()
    for ancestor in canonical.pathComponents.indices.reversed() {
      let candidate = URL(
        fileURLWithPath: NSString.path(
          withComponents: Array(canonical.pathComponents.prefix(ancestor + 1))))
      let projectDir = candidate.deletingLastPathComponent()
      if fileManager.fileExists(atPath: projectDir.appendingPathComponent(".project").path) {
        return TaskSummary(
          project: projectDir.lastPathComponent,
          task: candidate.lastPathComponent,
          path: candidate
        )
      }
    }
    throw HatchError.message("must be run from within a task folder")
  }
}
