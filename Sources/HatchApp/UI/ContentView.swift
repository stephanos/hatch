import HatchAppState
import HatchCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var windowController: WindowActivationController

  var body: some View {
    Group {
      if let bootstrap = model.bootstrap, let config = model.workspaceConfig {
        MainWorkspaceView(
          model: model,
          windowController: windowController,
          bootstrap: bootstrap,
          workspaceConfig: config
        )
      } else {
        OnboardingView(model: model, windowController: windowController)
      }
    }
    .alert(item: $model.alertError) { error in
      Alert(title: Text("hatch"), message: Text(error.localizedDescription))
    }
  }
}
