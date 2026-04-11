import HatchAppState
import HatchCore
import SwiftUI

struct OnboardingView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var windowController: WindowActivationController
  @State private var workspaceRoot = "~/Workspace"
  @State private var cliInstallPath = "~/.local/bin"
  @State private var defaultOrg = ""
  @State private var defaultRepos = ""
  @State private var branchTemplate = "{user}/{task}"
  @State private var editor = ""
  @State private var hooksInclude: [String] = []

  var body: some View {
    ConfigurationScreen(
      mode: .setup,
      workspaceRoot: $workspaceRoot,
      cliInstallPath: $cliInstallPath,
      branchTemplate: $branchTemplate,
      defaultOrg: $defaultOrg,
      defaultRepos: $defaultRepos,
      editor: $editor,
      hooksInclude: $hooksInclude,
      onSubmit: {
        model.saveConfiguration(
          bootstrap: BootstrapConfig(
            workspaceRoot: workspaceRoot,
            cliInstallPath: cliInstallPath
          ),
          workspace: WorkspaceConfig(
            defaultOrg: defaultOrg,
            defaultRepos: defaultRepos.split(separator: ",").map {
              $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty },
            branchTemplate: branchTemplate,
            editor: editor,
            hooksInclude: hooksInclude,
            hooks: [:]
          )
        )
      }
    )
    .task {
      windowController.setDismissesOnResign(false)
      windowController.setPresentation(.configure)
      windowController.centerMainWindow()
    }
  }
}
