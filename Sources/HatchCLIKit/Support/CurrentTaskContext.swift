import Foundation
import HatchCore

package struct CurrentTaskContext {
  package let project: ProjectSummary
  package let task: TaskSummary

  package init(project: ProjectSummary, task: TaskSummary) {
    self.project = project
    self.task = task
  }
}

package func resolveCurrentTaskContext(
  from directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
)
  throws -> CurrentTaskContext
{
  let fileManager = FileManager.default
  let canonical = directory.resolvingSymlinksInPath()

  for ancestor in canonical.pathComponents.indices.reversed() {
    let candidate = URL(
      fileURLWithPath: NSString.path(
        withComponents: Array(canonical.pathComponents.prefix(ancestor + 1))))
    let projectDirectory = candidate.deletingLastPathComponent()

    if fileManager.fileExists(atPath: projectDirectory.appendingPathComponent(".project").path) {
      let project = ProjectSummary(name: projectDirectory.lastPathComponent, path: projectDirectory)
      let task = TaskSummary(
        project: project.name,
        task: candidate.lastPathComponent,
        path: candidate
      )
      return CurrentTaskContext(project: project, task: task)
    }
  }

  throw HatchError.message("must be run from within a task folder")
}
