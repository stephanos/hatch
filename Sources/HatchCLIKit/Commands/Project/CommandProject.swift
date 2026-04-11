import HatchCore

extension HatchCLI {
  static func runProject(arguments: [String]) throws {
    guard let subcommand = arguments.first else {
      throw CLIError(
        message: "usage: \(CLIConstants.executableName) project <create|list|config> ...")
    }

    switch subcommand {
    case "create":
      try createProject(arguments: Array(arguments.dropFirst()))
    case "list":
      try listProjects(arguments: Array(arguments.dropFirst()))
    case "config":
      try openProjectConfig(arguments: Array(arguments.dropFirst()))
    default:
      throw CLIError(message: "unknown project command '\(subcommand)'")
    }
  }

  private static func createProject(arguments: [String]) throws {
    guard arguments.count == 1 else {
      throw CLIError(message: "usage: \(CLIConstants.executableName) project create <project-name>")
    }

    let behavior = LiveHatchBehavior()
    let state = try requireConfiguredState(using: behavior)
    let project = try behavior.createProject(
      name: arguments[0],
      paths: state.paths,
      config: state.workspaceConfig
    )
    print(project.path.path)
  }

  private static func listProjects(arguments: [String]) throws {
    guard arguments.isEmpty else {
      throw CLIError(message: "usage: \(CLIConstants.executableName) project list")
    }

    let state = try LiveHatchBehavior().loadAppState()
    for project in state.projects {
      print(project.name)
    }
  }

  private static func openProjectConfig(arguments: [String]) throws {
    guard arguments.count == 1 else {
      throw CLIError(message: "usage: \(CLIConstants.executableName) project config <project-name>")
    }

    let behavior = LiveHatchBehavior()
    let state = try requireConfiguredAppState(using: behavior)
    guard let workspaceConfig = state.workspaceConfig else {
      throw HatchError.message("hatch is not configured")
    }
    guard let project = state.projects.first(where: { $0.name == arguments[0] }) else {
      throw HatchError.message("project \(arguments[0]) does not exist")
    }

    try behavior.openProjectConfig(project, editor: workspaceConfig.editor)
    print(project.path.appendingPathComponent("hatch.toml").path)
  }
}
