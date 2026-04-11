import HatchSupport

extension HatchUIScenario {
  var initialTarget: HatchPanelTarget {
    switch self {
    case .none:
      .commands
    case .configure:
      .configure
    case .createProject, .startTaskPickProject, .createTask, .resumeTask:
      .commands
    }
  }
}
