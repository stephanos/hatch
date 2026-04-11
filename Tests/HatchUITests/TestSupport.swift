import AppKit
import HatchSupport
import XCTest

extension HatchUIBaseTestCase {
  @discardableResult
  @MainActor
  func launchApp(scenario: String? = nil, query: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment[HatchEnvironment.Key.uiTestMode] = "1"
    app.launchEnvironment[HatchEnvironment.Key.uiTestConfigDir] = configDir.path
    app.launchEnvironment[HatchEnvironment.Key.uiTestWorkspaceRoot] = workspaceRoot.path
    if let scenario {
      app.launchEnvironment[HatchEnvironment.Key.uiTestScenario] = scenario
    }
    if let query {
      app.launchEnvironment[HatchEnvironment.Key.uiTestQuery] = query
    }
    app.launch()
    return app
  }

  @MainActor
  func seedConfiguredState(editor: String? = nil, recentProjects: [String] = []) throws {
    try HatchUIFixture.seedConfiguredState(
      configDir: configDir,
      workspaceRoot: workspaceRoot,
      editor: editor ?? "\"\(editorStubPath.path)\" --wait",
      recentProjects: recentProjects
    )
  }

  @MainActor
  func seedPopulatedWorkspace() throws {
    try HatchUIFixture.seedProjects(
      workspaceRoot: workspaceRoot,
      projects: HatchUIFixture.populatedProjects
    )
  }

  @MainActor
  func seedProjectOverflowWorkspace(projectCount: Int = 18) throws {
    let fileManager = FileManager.default
    for index in 1...projectCount {
      let name = String(format: "proj-%02d", index)
      let projectDirectory = workspaceRoot.appendingPathComponent(name, isDirectory: true)
      try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
      try "".write(
        to: projectDirectory.appendingPathComponent(".project"),
        atomically: true,
        encoding: .utf8
      )
    }
  }

  @MainActor
  func writeProjectConfig(projectName: String, contents: String) throws {
    try contents.write(
      to: workspaceRoot.appendingPathComponent("\(projectName)/hatch.toml"),
      atomically: true,
      encoding: .utf8
    )
  }

  func readWorkspaceConfig() throws -> String {
    try String(
      contentsOf: workspaceRoot.appendingPathComponent(".hatch/config.toml"),
      encoding: .utf8
    )
  }

  @MainActor
  func attachScreenshot(named name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @MainActor
  func spotlightInput(in app: XCUIApplication) -> XCUIElement {
    let identified = app.textFields["spotlight-input"]
    return identified.exists ? identified : app.textFields.firstMatch
  }

  @MainActor
  func waitForWindowToClose(in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
    let predicate = NSPredicate(format: "count == 0")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.windows)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  @MainActor
  func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let predicate = NSPredicate(format: "exists == false")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  @MainActor
  func clearAndType(text: String, into element: XCUIElement) {
    let app = XCUIApplication()
    app.activate()
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    app.typeKey("a", modifierFlags: .command)
    app.typeKey(.delete, modifierFlags: [])
    if !text.isEmpty {
      app.typeText(text)
    }
  }

  @MainActor
  func isMainWindowCentered(in app: XCUIApplication, tolerance: CGFloat = 32) -> Bool {
    guard
      let visibleFrame = NSScreen.main?.visibleFrame,
      app.windows.element(boundBy: 0).waitForExistence(timeout: 5)
    else {
      return false
    }

    let frame = app.windows.element(boundBy: 0).frame
    let horizontalDelta = abs(frame.midX - visibleFrame.midX)
    let verticalDelta = abs(frame.midY - visibleFrame.midY)
    return horizontalDelta <= tolerance && verticalDelta <= tolerance
  }

  @MainActor
  func standardCloseControl(in app: XCUIApplication) -> XCUIElement {
    let window = app.windows.element(boundBy: 0)
    let closeCandidates = window.buttons.matching(NSPredicate(format: "label == 'Close'"))
    if closeCandidates.count > 0 {
      return closeCandidates.firstMatch
    }
    return window.buttons.firstMatch
  }

  @MainActor
  func waitForWindowHeight(
    in app: XCUIApplication,
    toSatisfy predicate: @escaping (CGFloat) -> Bool,
    timeout: TimeInterval = 5
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let window = app.windows.element(boundBy: 0)
      if window.waitForExistence(timeout: 0.1), predicate(window.frame.height) {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return false
  }
}
