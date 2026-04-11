import Foundation
import HatchCore

extension HatchCLI {
  static func runCheckout(arguments: [String]) throws {
    let parsed = try parseCheckoutArguments(arguments)

    let behavior = LiveHatchBehavior()
    let state = try requireConfiguredState(using: behavior)
    let context = try resolveCurrentTaskContext()
    let projectConfig = try behavior.loadProjectConfig(for: context.project)

    try behavior.addRepo(
      repoInput: parsed.repoInput,
      taskDirectory: context.task.path,
      projectConfig: projectConfig,
      paths: state.paths,
      config: state.workspaceConfig,
      force: parsed.force
    )
  }
}

package struct CheckoutArguments {
  package let force: Bool
  package let repoInput: String

  package init(force: Bool, repoInput: String) {
    self.force = force
    self.repoInput = repoInput
  }
}

package func parseCheckoutArguments(_ arguments: [String]) throws -> CheckoutArguments {
  let force = arguments.contains("--force")
  let positional = arguments.filter { $0 != "--force" }
  guard positional.count == 1 else {
    throw CLIError(
      message: "usage: \(CLIConstants.executableName) checkout [--force] <repo-or-url>")
  }
  return CheckoutArguments(force: force, repoInput: positional[0])
}
