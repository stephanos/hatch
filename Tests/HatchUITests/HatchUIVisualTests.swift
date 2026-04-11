import XCTest

final class HatchUIVisualTests: HatchUIBaseTestCase {
  @MainActor
  func testVisualSetupWindow() throws {
    let app = launchApp(scenario: "configure")

    XCTAssertTrue(app.staticTexts["Workspace Root"].waitForExistence(timeout: 5))
    attachScreenshot(named: "setup-window")
  }

  @MainActor
  func testVisualConfigureEmptyWorkspace() throws {
    let app = launchApp(scenario: "configure")

    XCTAssertTrue(app.staticTexts["Workspace Root"].waitForExistence(timeout: 5))
    attachScreenshot(named: "hatch-configure-empty")
  }

  @MainActor
  func testVisualSetupDisabledSubmitState() throws {
    let app = launchApp(scenario: "configure")

    let editorField = app.textFields["configuration-editor-field"]
    XCTAssertTrue(editorField.waitForExistence(timeout: 5))
    clearAndType(text: "", into: editorField)
    attachScreenshot(named: "setup-disabled-submit")
  }

  @MainActor
  func testVisualConfigureBeforeCancel() throws {
    try seedConfiguredState(editor: "zed")
    let app = launchApp(scenario: "configure")

    let editorField = app.textFields["configuration-editor-field"]
    XCTAssertTrue(editorField.waitForExistence(timeout: 5))
    clearAndType(text: "cursor", into: editorField)
    attachScreenshot(named: "configure-before-cancel")
  }

  @MainActor
  func testVisualConfigureBeforeSave() throws {
    try seedConfiguredState(editor: "zed")
    let app = launchApp(scenario: "configure")

    let editorField = app.textFields["configuration-editor-field"]
    XCTAssertTrue(editorField.waitForExistence(timeout: 5))
    clearAndType(text: "cursor", into: editorField)
    attachScreenshot(named: "configure-before-save")
  }

  @MainActor
  func testVisualStartTaskFlow() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(app.staticTexts["Choose which project this task belongs to."].waitForExistence(timeout: 5))
    input.typeText("alp")
    XCTAssertTrue(element(in: app, identifier: "project-pill-primary-alpha").waitForExistence(timeout: 5))
    attachScreenshot(named: "start-task-project-filter-alpha")
    input.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.staticTexts["Choose a short name for the new task in alpha."].waitForExistence(timeout: 5))
    attachScreenshot(named: "start-task-task-entry-alpha")
  }

  @MainActor
  func testVisualStartTaskProjectRanking() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.typeText("al")
    XCTAssertTrue(element(in: app, identifier: "project-pill-primary-alpha").waitForExistence(timeout: 5))
    attachScreenshot(named: "start-task-project-ranking-alpha")
  }

  @MainActor
  func testVisualProjectPickerOverflow() throws {
    try seedConfiguredState()
    try seedProjectOverflowWorkspace()
    let app = launchApp(scenario: "start-task-pick-project")

    XCTAssertTrue(app.staticTexts["Choose which project this task belongs to."].waitForExistence(timeout: 5))
    attachScreenshot(named: "start-task-project-picker-overflow")
  }

  @MainActor
  func testVisualCommandRanking() throws {
    try seedConfiguredState()
    let app = launchApp()

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.typeText("st")
    XCTAssertTrue(
      element(in: app, identifier: "spotlight-command-primary-start-task").waitForExistence(timeout: 5)
    )
    attachScreenshot(named: "spotlight-command-primary-start-task")
  }

  @MainActor
  func testVisualCreateProjectInvalidName() throws {
    try seedConfiguredState()
    let app = launchApp(scenario: "create-project")

    let input = spotlightInput(in: app)
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    clearAndType(text: "bad name", into: input)
    XCTAssertTrue(app.staticTexts["Project names cannot contain spaces."].waitForExistence(timeout: 5))
    attachScreenshot(named: "create-project-invalid-name")
  }

  @MainActor
  func testVisualCreateTaskStates() throws {
    try seedConfiguredState()
    try seedPopulatedWorkspace()
    let app = launchApp(scenario: "create-task")

    XCTAssertTrue(app.staticTexts["Choose a short name for the new task in alpha."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["alpha/release-notes"].exists)
    attachScreenshot(named: "hatch-create-task-populated")
  }

  @MainActor
  func testVisualCreateTaskOverflowPreview() throws {
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

    XCTAssertTrue(app.staticTexts["Choose a short name for the new task in alpha."].waitForExistence(timeout: 5))
    XCTAssertTrue(element(in: app, identifier: "task-preview-branch-design").waitForExistence(timeout: 5))
    attachScreenshot(named: "create-task-preview-overflow")
  }

  @MainActor
  func testVisualResumeTaskStates() throws {
    try seedConfiguredState(recentProjects: ["alpha"])
    try seedPopulatedWorkspace()

    let noMatchApp = launchApp(scenario: "resume-task", query: "zzz")
    XCTAssertTrue(noMatchApp.staticTexts["No matching task."].waitForExistence(timeout: 5))
    attachScreenshot(named: "resume-task-no-match")
    noMatchApp.terminate()

    let rankedApp = launchApp(scenario: "resume-task", query: "setup")
    XCTAssertTrue(appStaticText(rankedApp, "Pick a task to resume.").waitForExistence(timeout: 5))
    XCTAssertTrue(
      element(in: rankedApp, identifier: "task-pill-primary-alpha-setup-ci").waitForExistence(timeout: 5)
    )
    attachScreenshot(named: "resume-task-primary-alpha-setup-ci")
    rankedApp.terminate()

    let populatedApp = launchApp(scenario: "resume-task", query: "i")
    let input = spotlightInput(in: populatedApp)
    XCTAssertTrue(appStaticText(populatedApp, "Pick a task to resume.").waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, "i")
    attachScreenshot(named: "hatch-resume-task-populated")
  }

  @MainActor
  private func appStaticText(_ app: XCUIApplication, _ text: String) -> XCUIElement {
    app.staticTexts[text]
  }
}
