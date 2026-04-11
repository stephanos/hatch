import Foundation

public enum HatchEnvironment {
  public enum Key {
    public static let uiTestMode = "HATCH_UI_TEST_MODE"
    public static let demoMode = "HATCH_DEMO_MODE"
    public static let uiTestScenario = "HATCH_UI_TEST_SCENARIO"
    public static let demoScenario = "HATCH_DEMO_SCENARIO"
    public static let uiTestQuery = "HATCH_UI_TEST_QUERY"
    public static let demoQuery = "HATCH_DEMO_QUERY"
    public static let uiTestConfigDir = "HATCH_UI_TEST_CONFIG_DIR"
    public static let uiTestWorkspaceRoot = "HATCH_UI_TEST_WORKSPACE_ROOT"
    public static let configDir = "HATCH_CONFIG_DIR"
    public static let xdgConfigHome = "XDG_CONFIG_HOME"
    public static let xcodeUITestConfiguration = "XCTestConfigurationFilePath"
  }
}
