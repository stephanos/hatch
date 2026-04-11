import HatchAppState
import HatchCore
import HatchSupport
import SwiftUI

struct MainWorkspaceView: View {
  private let runtimeMode: HatchRuntimeMode
  @ObservedObject var model: AppModel
  @ObservedObject var windowController: WindowActivationController
  @State var bootstrap: BootstrapConfig
  @State var workspaceConfig: WorkspaceConfig
  @State private var request: HatchPanelRequest
  @State private var paletteContentHeight: CGFloat = 0

  init(
    model: AppModel,
    windowController: WindowActivationController,
    bootstrap: BootstrapConfig,
    workspaceConfig: WorkspaceConfig
  ) {
    let runtimeMode = HatchRuntimeMode.current()
    self.runtimeMode = runtimeMode
    self.model = model
    self.windowController = windowController
    _bootstrap = State(initialValue: bootstrap)
    _workspaceConfig = State(initialValue: workspaceConfig)
    _request = State(
      initialValue: HatchPanelRequest(
        target: runtimeMode.isAutomation ? runtimeMode.scenario.initialTarget : .commands)
    )
  }

  var body: some View {
    Group {
      if request.target == .configure {
        SpotlightConfigurationView(
          model: model,
          bootstrap: $bootstrap,
          workspaceConfig: $workspaceConfig,
          onSaved: {
            request = HatchPanelRequest(target: .commands)
            windowController.dismissMainWindow()
          },
          onBack: {
            request = HatchPanelRequest(target: .commands)
            windowController.dismissMainWindow()
          }
        )
      } else {
        SpotlightPanelView(
          model: model,
          windowController: windowController,
          bootstrap: $bootstrap,
          workspaceConfig: $workspaceConfig,
          request: request,
          onOpenConfiguration: {
            request = HatchPanelRequest(target: .configure)
          }
        )
        .background(
          GeometryReader { geometry in
            Color.clear.preference(
              key: PaletteContentHeightPreferenceKey.self,
              value: geometry.size.height
            )
          }
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: AppWindowMetrics.spotlightPanelWidth, alignment: .top)
      }
    }
    .task {
      windowController.setOpenCommandPaletteAction { shouldResetState in
        request = HatchPanelRequest(target: .commands, shouldResetState: shouldResetState)
      }
      windowController.setOpenConfigurationAction { shouldResetState in
        request = HatchPanelRequest(target: .configure, shouldResetState: shouldResetState)
      }
      if let pendingRequest = windowController.consumePendingPanelRequest() {
        request = pendingRequest
      } else if runtimeMode.isAutomation {
        request = HatchPanelRequest(target: runtimeMode.scenario.initialTarget)
      }
    }
    .onChange(of: request.target) { _, newTarget in
      windowController.setDismissesOnResign(!runtimeMode.isAutomation && newTarget != .configure)
      windowController.setPresentation(newTarget == .configure ? .configure : .palette)
      if newTarget == .configure {
        windowController.centerMainWindow()
      }
    }
    .onAppear {
      windowController.setDismissesOnResign(
        !runtimeMode.isAutomation && request.target != .configure
      )
      windowController.setPresentation(request.target == .configure ? .configure : .palette)
      if request.target == .configure {
        windowController.centerMainWindow()
      }
    }
    .onPreferenceChange(PaletteContentHeightPreferenceKey.self) { height in
      guard request.target != .configure, height > 0 else { return }
      let shouldAnimate = paletteContentHeight > 0
      paletteContentHeight = height
      windowController.resizePaletteWindow(height: height, animated: shouldAnimate)
    }
    .onChange(of: model.bootstrap) { _, newValue in
      if let newValue {
        bootstrap = newValue
      }
    }
    .onChange(of: model.workspaceConfig) { _, newValue in
      if let newValue {
        workspaceConfig = newValue
      }
    }
  }
}

private struct PaletteContentHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
