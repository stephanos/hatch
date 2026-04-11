import Foundation

struct HookRunner {
  let runner: ProcessRunner
  let reporter: (any HookFailureReporter)?

  func run(
    _ hookName: HookName,
    context: HookContext,
    config: WorkspaceConfig
  ) throws {
    let merged = BuiltinHookCatalog.merged(config: config)
    guard let hook = merged[hookName] else {
      return
    }

    do {
      switch hook {
      case .builtin(let action, _):
        try action.run(context: context)
      case .command(let definition):
        try runCommand(definition, context: context)
      }
    } catch {
      switch hook.errorPolicy {
      case .ignore:
        return
      case .warn:
        reporter?.report(
          HookFailureEvent(
            hookName: hookName,
            errorPolicy: .warn,
            message: error.localizedDescription,
            project: context.project,
            task: context.task,
            repoInput: context.repoInput
          )
        )
        NSLog("Hook \(hookName.rawValue) failed: \(error.localizedDescription)")
      case .fail:
        throw error
      }
    }
  }

  private func runCommand(_ hook: HookDefinition, context: HookContext) throws {
    guard let program = hook.command.first else {
      throw HatchError.message("hook command cannot be empty")
    }
    let workingDirectory =
      [context.taskPath, context.projectPath, context.workspaceRoot]
      .compactMap { $0 }
      .first(where: { FileManager.default.fileExists(atPath: $0.path) }) ?? context.workspaceRoot
    try runner.run(
      program,
      arguments: Array(hook.command.dropFirst()),
      currentDirectory: workingDirectory,
      environment: context.environment()
    )
  }
}

enum HookResolution {
  case command(HookDefinition)
  case builtin(BuiltinHookAction, errorPolicy: HookErrorPolicy)

  var errorPolicy: HookErrorPolicy {
    switch self {
    case .command(let definition):
      return definition.onError
    case .builtin(_, let errorPolicy):
      return errorPolicy
    }
  }
}
