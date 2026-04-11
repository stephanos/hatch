enum SpotlightStep: Equatable {
  case commands
  case newProject
  case newTask
  case openTask
  case openProjectConfig
  case configure

  var prompt: String {
    switch self {
    case .commands:
      return "Search hatch"
    case .newProject:
      return "Project name"
    case .newTask:
      return "Task name"
    case .openTask:
      return "Search tasks"
    case .openProjectConfig:
      return "Search projects"
    case .configure:
      return "Configure hatch"
    }
  }

  var subtitle: String {
    switch self {
    case .commands:
      return ""
    case .newProject:
      return "Create a workspace project."
    case .newTask:
      return "Create a task in a project."
    case .openTask:
      return "Open an existing task."
    case .openProjectConfig:
      return "Open a project's config file."
    case .configure:
      return "Update settings."
    }
  }

  var usesSearchField: Bool {
    self != .configure
  }

  var defaultFocus: SpotlightField? {
    switch self {
    case .commands:
      return .commandSearch
    case .newProject:
      return .projectName
    case .newTask:
      return .taskName
    case .openTask, .openProjectConfig:
      return .itemSearch
    case .configure:
      return nil
    }
  }
}
