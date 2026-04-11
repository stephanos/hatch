import HatchAppState
import HatchCore
import HatchSupport
import SwiftUI

struct SpotlightPanelView: View {
  private let runtimeMode = HatchRuntimeMode.current()
  @ObservedObject var model: AppModel
  @ObservedObject var windowController: WindowActivationController
  @Binding var bootstrap: BootstrapConfig
  @Binding var workspaceConfig: WorkspaceConfig
  let request: HatchPanelRequest
  let onOpenConfiguration: () -> Void

  @StateObject private var session = SpotlightSession(
    queryOverride: HatchRuntimeMode.current().queryOverride
  )
  @FocusState private var isInputFocused: Bool
  @State private var panelContentHeight: CGFloat = 0

  var body: some View {
    panelContent
      .background(
        GeometryReader { geometry in
          Color.clear.preference(
            key: SpotlightPanelHeightPreferenceKey.self,
            value: geometry.size.height
          )
        }
      )
      .frame(
        width: AppWindowMetrics.spotlightPanelWidth,
        height: displayedPanelHeight,
        alignment: .top
      )
      .animation(.easeInOut(duration: 0.2), value: displayedPanelHeight)
      .onPreferenceChange(SpotlightPanelHeightPreferenceKey.self) { height in
        guard height > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
          panelContentHeight = height
        }
      }
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.14), radius: 30, y: 14)
      .background(
        SpotlightBackspaceMonitor(
          isEnabled: session.selectedCommand != nil && session.inputText.isEmpty,
          onBackspace: stepBackAtEmptyInput,
          onEscape: dismissPanelAndResetState
        )
      )
      .onAppear {
        apply(request.target)
        applyDemoScenarioIfNeeded()
      }
      .onChange(of: request) { _, newRequest in
        apply(newRequest.target)
        applyDemoScenarioIfNeeded()
      }
      .onChange(of: session.selectedCommand) { _, newCommand in
        if newCommand != .newTask {
          session.selectedProjectName = nil
        }
        isInputFocused = true
      }
      .onChange(of: session.inputText) { _, newValue in
        guard shouldNormalizeInputCase else {
          return
        }

        let normalizedValue = newValue.lowercased()
        if normalizedValue != newValue {
          session.inputText = normalizedValue
        }
      }
  }

  private var panelContent: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .bottom, spacing: 9) {
          Image(nsImage: MenuBarAssets.spotlightImage)
            .accessibilityHidden(true)

          if let selectedCommand = session.selectedCommand {
            SpotlightCommandPill(command: selectedCommand)
          }

          if let selectedProjectName = session.selectedProjectName,
            session.selectedCommand == .newTask
          {
            SpotlightTextPill(text: selectedProjectName, isPrimaryMatch: true)
          }

          TextField(currentPrompt, text: $session.inputText)
            .textFieldStyle(.plain)
            .font(.system(size: 29, weight: .regular))
            .foregroundStyle(.primary)
            .accessibilityIdentifier("spotlight-input")
            .focused($isInputFocused)
            .onSubmit(handleSubmit)

          Spacer(minLength: 0)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 12)

      Divider()
        .overlay(Color.white.opacity(0.28))

      commandContent
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
  }

  private var displayedPanelHeight: CGFloat? {
    guard panelContentHeight > 0 else {
      return nil
    }

    return min(panelContentHeight, AppWindowMetrics.spotlightPanelHeight)
  }

  @ViewBuilder
  private var commandContent: some View {
    switch session.selectedCommand {
    case nil:
      SpotlightCommandList(
        commands: suggestedCommands,
        highlightsPrimaryMatch: isFilteringCommandChoices
      )
    case .newProject:
      SpotlightNewProjectView(
        name: $session.inputText,
        error: projectNameError,
        preview: newProjectPreview
      )
    case .newTask:
      VStack(alignment: .leading, spacing: 8) {
        SpotlightNewTaskView(
          isSelectingProject: session.selectedProjectName == nil,
          projectName: session.selectedProjectName,
          error: newTaskError,
          preview: newTaskPreview
        )

        if session.selectedProjectName == nil {
          SpotlightProjectPreviewList(
            projects: suggestedProjects,
            highlightsPrimaryMatch: isFilteringProjectChoices
          )
          .accessibilityIdentifier("project-picker-list")
        }
      }
    case .openTask:
      VStack(alignment: .leading, spacing: 8) {
        SpotlightOpenTaskView(error: openTaskError)
        SpotlightTaskPreviewList(
          tasks: filteredTasks,
          highlightsPrimaryMatch: isFilteringTaskChoices
        )
        .accessibilityIdentifier("resume-task-list")
      }
    case .configure:
      EmptyView()
    }
  }

  private var currentPrompt: String {
    if session.selectedCommand == .newTask {
      return session.selectedProjectName == nil ? "project-name" : "task-name"
    }
    return session.selectedCommand?.argumentPrompt ?? ""
  }

  private var shouldNormalizeInputCase: Bool {
    switch session.selectedCommand {
    case nil, .newProject, .newTask:
      return true
    case .openTask, .configure:
      return false
    }
  }

  private var matchingCommands: [SpotlightCommand] {
    SpotlightMatcher.matchingCommands(query: session.inputText)
  }

  private var suggestedCommands: [SpotlightCommand] {
    if session.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return matchingCommands
    }
    return matchingCommands.first.map { [$0] } ?? []
  }

  private var isFilteringCommandChoices: Bool {
    session.selectedCommand == nil
      && !session.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var matchingProjects: [ProjectSummary] {
    SpotlightMatcher.matchingProjects(query: session.inputText, projects: model.projects)
  }

  private var suggestedProjects: [ProjectSummary] {
    matchingProjects
  }

  private var isFilteringProjectChoices: Bool {
    session.selectedCommand == .newTask
      && session.selectedProjectName == nil
      && !session.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var isFilteringTaskChoices: Bool {
    session.selectedCommand == .openTask
      && !session.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var filteredTasks: [TaskSummary] {
    SpotlightMatcher.filteredTasks(
      query: session.inputText,
      tasks: model.tasks,
      recentProjects: model.recentProjects
    )
  }

  private var projectNameError: String? {
    SpotlightValidation.projectNameError(input: session.inputText, projects: model.projects)
  }

  private var newProjectPreview: ProjectCreationPreview? {
    guard session.selectedCommand == .newProject, projectNameError == nil else {
      return nil
    }

    let trimmed = session.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    return model.previewProjectCreation(name: trimmed)
  }

  private var newTaskError: String? {
    SpotlightValidation.newTaskError(
      input: session.inputText,
      selectedProjectName: session.selectedProjectName,
      matchingProjects: matchingProjects,
      tasks: model.tasks
    )
  }

  private var openTaskError: String? {
    SpotlightValidation.openTaskError(input: session.inputText, filteredTasks: filteredTasks)
  }

  private var newTaskPreview: TaskCreationPreview? {
    guard
      session.selectedCommand == .newTask,
      let selectedProjectName = session.selectedProjectName,
      newTaskError == nil
    else {
      return nil
    }

    let trimmed = session.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    return model.previewTaskCreation(projectName: selectedProjectName, taskName: trimmed)
  }

  private func handleSubmit() {
    let trimmedInput = session.inputText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let selectedCommand = session.selectedCommand else {
      guard !trimmedInput.isEmpty else {
        return
      }
      if let suggestion = matchingCommands.first {
        selectCommand(suggestion)
      }
      return
    }

    switch selectedCommand {
    case .newProject:
      submitNewProject()
    case .newTask:
      if session.selectedProjectName == nil {
        guard !trimmedInput.isEmpty else {
          return
        }
        if let project = matchingProjects.first {
          session.selectedProjectName = project.name
          session.inputText = ""
        }
      } else {
        submitNewTask()
      }
    case .openTask:
      guard !trimmedInput.isEmpty else {
        return
      }
      if let task = filteredTasks.first {
        model.openTask(task)
        session.clearCommandSelection()
      }
    case .configure:
      onOpenConfiguration()
    }
  }

  private func selectCommand(_ command: SpotlightCommand) {
    if command == .configure {
      onOpenConfiguration()
      return
    }
    session.selectedCommand = command
    session.inputText = ""
    isInputFocused = true
  }

  private func submitNewProject() {
    let trimmed = session.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, projectNameError == nil else { return }
    model.createProject(named: trimmed)
    session.clearCommandSelection()
  }

  private func submitNewTask() {
    let trimmed = session.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let selectedProjectName = session.selectedProjectName,
      !trimmed.isEmpty,
      newTaskError == nil
    else {
      return
    }
    model.createTask(projectName: selectedProjectName, taskName: trimmed)
    session.clearCommandSelection()
  }

  private func apply(_ target: HatchPanelTarget) {
    if request.shouldResetState {
      session.clearCommandSelection()
    }

    switch target {
    case .commands:
      isInputFocused = true
    case .configure:
      break
    }
  }

  private func applyDemoScenarioIfNeeded() {
    session.applyDemoScenarioIfNeeded(runtimeMode.scenario)
    isInputFocused = true
  }

  private func stepBackAtEmptyInput() {
    session.stepBackAtEmptyInput()
    isInputFocused = true
  }

  private func dismissPanel() {
    windowController.dismissMainWindow()
  }

  private func dismissPanelAndResetState() {
    session.clearCommandSelection()
    dismissPanel()
  }
}

private struct SpotlightPanelHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
