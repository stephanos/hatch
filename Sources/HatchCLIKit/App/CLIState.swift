import HatchCore

extension HatchCLI {
  static func requireConfiguredState(using behavior: LiveHatchBehavior) throws
    -> (paths: AppPaths, workspaceConfig: WorkspaceConfig)
  {
    let state = try behavior.loadAppState()
    guard state.bootstrap != nil, let workspaceConfig = state.workspaceConfig else {
      throw HatchError.message("hatch is not configured")
    }
    return (state.paths, workspaceConfig)
  }

  static func requireConfiguredAppState(using behavior: LiveHatchBehavior) throws
    -> LoadedAppState
  {
    let state = try behavior.loadAppState()
    guard state.bootstrap != nil, state.workspaceConfig != nil else {
      throw HatchError.message("hatch is not configured")
    }
    return state
  }
}
