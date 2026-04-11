enum ConfigurationScreenMode {
  case setup
  case configure

  var title: String {
    switch self {
    case .setup:
      return "Setup"
    case .configure:
      return "Configure"
    }
  }

  var subtitle: String {
    switch self {
    case .setup:
      return
        "Choose your workspace root and CLI install location now. You can update the rest later."
    case .configure:
      return ""
    }
  }

  var actionTitle: String {
    switch self {
    case .setup:
      return "Finish setup"
    case .configure:
      return "Save changes"
    }
  }

  var showsBackButton: Bool {
    self == .configure
  }

  var showsEditorField: Bool {
    true
  }

  var workspaceRootDetail: String {
    switch self {
    case .setup:
      return
        "This directory will contain your projects and hatch's config. It is set during setup."
    case .configure:
      return
        "This directory contains your projects and hatch's config. It was set during setup and can't be changed here."
    }
  }

  var cliInstallPathDetail: String {
    switch self {
    case .setup:
      return
        "Directory where hatch should install the terminal symlink when you finish setup. It is set during setup."
    case .configure:
      return
        "Directory where hatch installed the terminal symlink during setup. It was set during setup and can't be changed here."
    }
  }

  var cliInstallPathIsEditable: Bool {
    self == .setup
  }

  var workspaceRootIsEditable: Bool {
    self == .setup
  }
}
