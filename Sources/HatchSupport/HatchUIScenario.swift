import Foundation

public enum HatchUIScenario: String, CaseIterable, Sendable {
  case none
  case configure = "configure"
  case createProject = "create-project"
  case startTaskPickProject = "start-task-pick-project"
  case createTask = "create-task"
  case resumeTask = "resume-task"
}
