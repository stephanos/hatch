import CoreGraphics
import HatchSupport
import XCTest

class HatchUIBaseTestCase: XCTestCase {
  var tempRoot: URL!
  var configDir: URL!
  var workspaceRoot: URL!
  var editorStubPath: URL!
  var editorLog: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    let fileManager = FileManager.default
    tempRoot = fileManager.temporaryDirectory.appendingPathComponent(
      "hatch-ui-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    configDir = tempRoot.appendingPathComponent("config", isDirectory: true)
    workspaceRoot = tempRoot.appendingPathComponent("Workspace", isDirectory: true)
    editorStubPath = tempRoot.appendingPathComponent("fake-editor", isDirectory: false)
    editorLog = tempRoot.appendingPathComponent("editor.log", isDirectory: false)
    try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    try """
      #!/bin/sh
      printf '%s\n' "$@" >> "\(editorLog.path)"
      touch "\(tempRoot.appendingPathComponent("editor-ran").path)"
      """
      .write(to: editorStubPath, atomically: true, encoding: .utf8)
    try fileManager.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: editorStubPath.path
    )
  }

  override func tearDownWithError() throws {
    MainActor.assumeIsolated {
      XCUIApplication().terminate()
    }
    if let tempRoot {
      try? FileManager.default.removeItem(at: tempRoot)
    }
  }
}

final class HatchUITests: HatchUIBaseTestCase {

  @MainActor
  func testSetupWindowIsCenteredAndShowsToolbarCloseControl() throws {
    let app = launchApp(scenario: "configure")

    XCTAssertTrue(app.staticTexts["Workspace Root"].waitForExistence(timeout: 5))
    XCTAssertTrue(isMainWindowCentered(in: app))
    XCTAssertTrue(standardCloseControl(in: app).waitForExistence(timeout: 5))
  }

  @MainActor
  func testConfigureEmptyWorkspace() throws {
    let app = launchApp(scenario: "configure")

    XCTAssertTrue(app.staticTexts["Workspace Root"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Branch Template"].exists)
    XCTAssertTrue(app.staticTexts["Editor"].exists)
  }

  @MainActor
  func testSetupDisabledSubmitState() throws {
    let app = launchApp(scenario: "configure")

    let editorField = app.textFields["configuration-editor-field"]
    XCTAssertTrue(editorField.waitForExistence(timeout: 5))
    clearAndType(text: "", into: editorField)

    XCTAssertFalse(element(in: app, identifier: "configuration-submit").isEnabled)
  }

  @MainActor
  func testFinishSetupWritesConfigurationFiles() throws {
    let app = launchApp(scenario: "configure")

    let workspaceField = app.textFields["configuration-workspace-root-field"]
    let cliField = app.textFields["configuration-cli-install-path-field"]
    let editorField = app.textFields["configuration-editor-field"]

    XCTAssertTrue(workspaceField.waitForExistence(timeout: 5))
    clearAndType(
      text: workspaceRoot.appendingPathComponent("Dev Workspace").path, into: workspaceField)
    clearAndType(text: workspaceRoot.appendingPathComponent("bin").path, into: cliField)
    clearAndType(text: "cursor", into: editorField)
    let submitButton = element(in: app, identifier: "configuration-submit")
    XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
    submitButton.click()

    XCTAssertTrue(
      waitForElementToDisappear(element(in: app, identifier: "configuration-screen-setup"))
    )
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: configDir.appendingPathComponent("config.toml").path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: workspaceRoot.appendingPathComponent("Dev Workspace/.hatch/config.toml").path
      )
    )
  }

  @MainActor
  func testCancelFromConfigureClosesWindowWithoutSaving() throws {
    try seedConfiguredState(editor: "zed")
    let app = launchApp(scenario: "configure")

    let editorField = app.textFields["configuration-editor-field"]
    XCTAssertTrue(editorField.waitForExistence(timeout: 5))
    clearAndType(text: "cursor", into: editorField)
    let cancelButton = element(in: app, identifier: "configuration-cancel")
    if cancelButton.waitForExistence(timeout: 2) {
      cancelButton.click()
    } else {
      standardCloseControl(in: app).click()
    }

    XCTAssertTrue(waitForWindowToClose(in: app))
    XCTAssertTrue(
      try readWorkspaceConfig().contains(#"editor = "zed""#)
    )
  }

  @MainActor
  func testSaveChangesFromConfigurePersistsAndClosesWindow() throws {
    try seedConfiguredState(editor: "zed")
    let app = launchApp(scenario: "configure")

    let editorField = app.textFields["configuration-editor-field"]
    XCTAssertTrue(editorField.waitForExistence(timeout: 5))
    clearAndType(text: "cursor", into: editorField)
    let submitButton = element(in: app, identifier: "configuration-submit")
    XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
    submitButton.click()

    XCTAssertTrue(waitForWindowToClose(in: app))
    XCTAssertTrue(
      try readWorkspaceConfig().contains(#"editor = "cursor""#)
    )
  }

  @MainActor
  func testTypingCommandAndSubmittingTransitionsToStartTask() throws {
    try seedConfiguredState()
    let app = launchApp()

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.typeText("st")
    input.typeKey(.return, modifierFlags: [])

    XCTAssertTrue(
      element(in: app, identifier: "spotlight-start-task-pick-project").waitForExistence(timeout: 5)
    )
  }

  @MainActor
  func testCommandRankingPrefersStartTaskForSTQuery() throws {
    try seedConfiguredState()
    let app = launchApp()

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.typeText("st")

    XCTAssertTrue(
      element(in: app, identifier: "spotlight-command-primary-start-task").waitForExistence(
        timeout: 5)
    )
  }

  @MainActor
  func testClickingOutsideSpotlightClosesWindow() throws {
    try seedConfiguredState()
    let app = launchApp()

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))

    let window = app.windows.element(boundBy: 0)
    XCTAssertTrue(window.waitForExistence(timeout: 5))
    window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).click()

    XCTAssertTrue(waitForWindowToClose(in: app))
  }

  @MainActor
  func testStartTaskSubmittingProjectTransitionsToTaskEntry() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(app.staticTexts["Choose which project this task belongs to."].waitForExistence(timeout: 5))
    input.typeText("alp")
    XCTAssertTrue(
      element(in: app, identifier: "project-pill-primary-alpha").waitForExistence(timeout: 5))
    input.typeKey(.return, modifierFlags: [])

    XCTAssertTrue(
      app.staticTexts["Choose a short name for the new task in alpha."].waitForExistence(timeout: 5)
    )
    XCTAssertFalse(element(in: app, identifier: "project-picker-list").exists)
  }

  @MainActor
  func testStartTaskBackspaceReturnsToProjectPicker() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.typeText("alp")
    input.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(
      app.staticTexts["Choose a short name for the new task in alpha."].waitForExistence(timeout: 5)
    )

    input.click()
    input.typeKey(.delete, modifierFlags: [])

    XCTAssertTrue(element(in: app, identifier: "project-picker-list").waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Choose which project this task belongs to."].exists)
  }

  @MainActor
  func testStartTaskTypingTaskNameExpandsSpotlightForPreview() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.typeText("alp")
    input.typeKey(.return, modifierFlags: [])

    let window = app.windows.element(boundBy: 0)
    XCTAssertTrue(window.waitForExistence(timeout: 5))
    let compactHeight = window.frame.height

    clearAndType(text: "release-notes", into: input)

    XCTAssertTrue(app.staticTexts["alpha/release-notes"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      waitForWindowHeight(in: app, toSatisfy: { $0 > compactHeight + 20 }),
      "expected spotlight window height to grow when the task preview appears"
    )
  }

  @MainActor
  func testOpenTaskBackspaceShrinksSpotlightWindow() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "resume-task")

    XCTAssertTrue(app.staticTexts["Pick a task to resume."].waitForExistence(timeout: 5))
    let window = app.windows.element(boundBy: 0)
    XCTAssertTrue(window.waitForExistence(timeout: 5))
    let expandedHeight = window.frame.height

    let input = spotlightInput(in: app)
    input.click()
    input.typeKey(.delete, modifierFlags: [])

    XCTAssertTrue(
      element(in: app, identifier: "spotlight-command-start-task").waitForExistence(timeout: 5))
    XCTAssertTrue(
      waitForWindowHeight(in: app, toSatisfy: { $0 < expandedHeight - 20 }),
      "expected spotlight window height to shrink after backing out of resume-task"
    )
  }

  @MainActor
  func testProjectRankingPrefersAlphaForALQuery() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.typeText("al")

    XCTAssertTrue(
      element(in: app, identifier: "project-pill-primary-alpha").waitForExistence(timeout: 5))
  }

  @MainActor
  func testProjectPickerOverflowScreenshot() throws {
    try seedConfiguredState()
    try seedProjectOverflowWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    XCTAssertTrue(app.staticTexts["Choose which project this task belongs to."].waitForExistence(timeout: 5))
  }

  @MainActor
  func testInvalidProjectNameShowsValidationMessage() throws {
    try seedConfiguredState()
    let app = launchApp(scenario: "create-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    clearAndType(text: "bad name", into: input)

    XCTAssertTrue(
      app.staticTexts["Project names cannot contain spaces."].waitForExistence(timeout: 5))
  }

  @MainActor
  func testCreateProjectShowsPreview() throws {
    try seedConfiguredState()
    let app = launchApp(scenario: "create-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    clearAndType(text: "alpha", into: input)

    XCTAssertTrue(app.staticTexts["alpha"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["alpha/hatch.toml"].waitForExistence(timeout: 5))
    attachScreenshot(named: "create-project-preview")
  }

  @MainActor
  func testInvalidTaskNameShowsValidationMessage() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.typeText("alpha")
    input.typeKey(.return, modifierFlags: [])
    clearAndType(text: "bad name", into: input)

    XCTAssertTrue(app.staticTexts["Task names cannot contain spaces."].waitForExistence(timeout: 5))
  }

  @MainActor
  func testStartTaskNoMatchingProjectShowsError() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.typeText("zzz")

    XCTAssertTrue(app.staticTexts["No matching project."].waitForExistence(timeout: 5))
  }

  @MainActor
  func testCreateTaskPopulatedWorkspace() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "create-task")

    XCTAssertTrue(
      app.staticTexts["Choose a short name for the new task in alpha."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["alpha/release-notes"].exists)
  }

  @MainActor
  func testCreateTaskOverflowPreviewScreenshot() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    try writeProjectConfig(
      projectName: "alpha",
      contents: """
        default_repos = ["api", "web", "ios", "android", "docs", "ops", "infra", "design"]
        [repo_base_branches]
        api = "main"
        web = "develop"
        ios = "main"
        android = "develop"
        docs = "main"
        ops = "main"
        infra = "develop"
        design = "main"
        """
    )
    let app = launchApp(scenario: "create-task")

    XCTAssertTrue(
      app.staticTexts["Choose a short name for the new task in alpha."].waitForExistence(timeout: 5))
    XCTAssertTrue(element(in: app, identifier: "task-preview-title").waitForExistence(timeout: 5))
  }

  @MainActor
  func testResumeTaskNoMatchShowsError() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "resume-task", query: "zzz")

    XCTAssertTrue(app.staticTexts["Pick a task to reopen."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["No matching task."].waitForExistence(timeout: 5))
  }

  @MainActor
  func testResumeTaskRankingPrefersAlphaSetupCiForSetupQuery() throws {
    try seedConfiguredState(recentProjects: ["alpha"])
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "resume-task", query: "setup")

    XCTAssertTrue(app.staticTexts["Pick a task to reopen."].waitForExistence(timeout: 5))
    XCTAssertTrue(
      element(in: app, identifier: "task-pill-primary-alpha-setup-ci").waitForExistence(timeout: 5)
    )
  }

  @MainActor
  func testResumeTaskPopulatedWorkspace() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "resume-task", query: "i")

    let input = spotlightInput(in: app)
    XCTAssertTrue(app.staticTexts["Pick a task to reopen."].waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, "i")
    XCTAssertTrue(element(in: app, identifier: "task-pill-alpha-setup-ci").exists)
    XCTAssertTrue(element(in: app, identifier: "task-pill-alpha-design-system").exists)
    XCTAssertTrue(element(in: app, identifier: "task-pill-beta-landing-page").exists)
    XCTAssertTrue(element(in: app, identifier: "task-pill-gamma-ios-shell").exists)
    XCTAssertTrue(element(in: app, identifier: "resume-task-list").exists)
  }
}
