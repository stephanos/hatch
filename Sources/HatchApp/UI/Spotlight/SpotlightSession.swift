import HatchSupport
import SwiftUI

@MainActor
final class SpotlightSession: ObservableObject {
  @Published var selectedCommand: SpotlightCommand?
  @Published var inputText = ""
  @Published var selectedProjectName: String?

  private let queryOverride: String?
  private var hasAppliedScenario = false

  init(queryOverride: String?) {
    self.queryOverride = queryOverride
  }

  func clearCommandSelection() {
    selectedCommand = nil
    selectedProjectName = nil
    inputText = ""
  }

  func stepBackAtEmptyInput() {
    if selectedCommand == .newTask, selectedProjectName != nil {
      selectedProjectName = nil
      inputText = ""
      return
    }

    clearCommandSelection()
  }

  func applyDemoScenarioIfNeeded(_ scenario: HatchUIScenario) {
    guard !hasAppliedScenario else { return }

    switch scenario {
    case .none, .configure:
      return
    case .createProject:
      hasAppliedScenario = true
      selectedCommand = .newProject
      inputText = "alpha"
    case .startTaskPickProject:
      hasAppliedScenario = true
      selectedCommand = .newTask
      selectedProjectName = nil
      inputText = ""
    case .createTask:
      hasAppliedScenario = true
      selectedCommand = .newTask
      selectedProjectName = "alpha"
      inputText = "release-notes"
    case .resumeTask:
      hasAppliedScenario = true
      selectedCommand = .openTask
      inputText = queryOverride ?? ""
    }
  }
}
