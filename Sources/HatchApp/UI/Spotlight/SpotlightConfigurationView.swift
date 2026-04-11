import HatchAppState
import HatchCore
import SwiftUI

struct SpotlightConfigurationView: View {
  @ObservedObject var model: AppModel
  @Binding var bootstrap: BootstrapConfig
  @Binding var workspaceConfig: WorkspaceConfig
  let onSaved: () -> Void
  let onBack: () -> Void

  var body: some View {
    ConfigurationScreen(
      mode: .configure,
      workspaceRoot: $bootstrap.workspaceRoot,
      cliInstallPath: $bootstrap.cliInstallPath,
      branchTemplate: $workspaceConfig.branchTemplate,
      defaultOrg: $workspaceConfig.defaultOrg,
      defaultRepos: Binding(
        get: { workspaceConfig.defaultRepos.joined(separator: ", ") },
        set: { value in
          workspaceConfig.defaultRepos =
            value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        }
      ),
      editor: Binding(
        get: { workspaceConfig.editor ?? "" },
        set: { workspaceConfig.editor = $0.isEmpty ? nil : $0 }
      ),
      hooksInclude: $workspaceConfig.hooksInclude,
      onSubmit: {
        model.saveConfiguration(bootstrap: bootstrap, workspace: workspaceConfig)
        onSaved()
      },
      onBack: onBack
    )
  }
}
