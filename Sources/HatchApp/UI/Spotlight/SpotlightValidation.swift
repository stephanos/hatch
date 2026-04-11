import Foundation
import HatchCore

enum SpotlightValidation {
  static func projectNameError(input: String, projects: [ProjectSummary]) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    if let error = IdentifierValidator.validationError(label: "Project names", value: trimmed) {
      return error
    }
    if projects.contains(where: { $0.name == trimmed }) {
      return "A project named \(trimmed) already exists."
    }
    return nil
  }

  static func newTaskError(
    input: String,
    selectedProjectName: String?,
    matchingProjects: [ProjectSummary],
    tasks: [TaskSummary]
  ) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    if selectedProjectName == nil {
      return matchingProjects.isEmpty ? "No matching project." : nil
    }

    if let error = IdentifierValidator.validationError(label: "Task names", value: trimmed) {
      return error
    }
    if tasks.contains(where: { $0.project == selectedProjectName && $0.task == trimmed }) {
      return "A task named \(trimmed) already exists in \(selectedProjectName ?? "")."
    }
    return nil
  }

  static func openTaskError(input: String, filteredTasks: [TaskSummary]) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, filteredTasks.isEmpty else {
      return nil
    }
    return "No matching task."
  }
}
