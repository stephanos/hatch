import AppKit
import HatchAppState
import HatchCore
import HatchSupport
import SwiftUI

@main
struct HatchApp: App {
  private let runtimeMode: HatchRuntimeMode
  @StateObject private var model: AppModel
  @StateObject private var launchAtLogin = LaunchAtLoginModel()
  @StateObject private var windowController: WindowActivationController
  @StateObject private var shortcutController: ShortcutController

  init() {
    let runtimeMode = HatchRuntimeMode.current()
    self.runtimeMode = runtimeMode
    NSApplication.shared.setActivationPolicy(runtimeMode.isAutomation ? .regular : .accessory)
    let hookFailureReporter: (any HookFailureReporter)? =
      runtimeMode.isAutomation ? nil : HookWarningNotificationReporter()
    let model = AppModel(
      behavior: LiveHatchBehavior(hookFailureReporter: hookFailureReporter)
    )
    model.reload()
    _model = StateObject(wrappedValue: model)
    let windowController = WindowActivationController(
      dismissesOnResign: !runtimeMode.isAutomation
    )
    _windowController = StateObject(wrappedValue: windowController)
    _shortcutController = StateObject(
      wrappedValue: ShortcutController(windowController: windowController))
  }

  var body: some Scene {
    mainWindowScene
    menuBarScene
  }

  private var mainWindowScene: some Scene {
    WindowGroup("hatch", id: "main") {
      MainWindowRootView(model: model, windowController: windowController)
        .task(id: model.isConfigured) {
          if runtimeMode.isAutomation {
            NSApplication.shared.activate(ignoringOtherApps: true)
          }
          if model.isConfigured && !runtimeMode.isAutomation {
            launchAtLogin.configureDefaultIfNeeded()
          }
        }
    }
    .windowStyle(.hiddenTitleBar)
    .defaultLaunchBehavior(
      runtimeMode.isAutomation ? .presented : (model.isConfigured ? .suppressed : .presented)
    )
    .defaultSize(
      width: AppWindowMetrics.mainWindowWidth,
      height: AppWindowMetrics.mainWindowHeight
    )
    .windowResizability(.automatic)
  }

  private var menuBarScene: some Scene {
    MenuBarExtra(
      isInserted: Binding(
        get: { model.isConfigured && !runtimeMode.isAutomation },
        set: { _ in }
      )
    ) {
      MenuBarContentView(
        launchAtLogin: launchAtLogin,
        windowController: windowController
      )
    } label: {
      MenuBarLabelView(windowController: windowController)
    }
  }
}

private struct MenuBarContentView: View {
  @ObservedObject private var shortcutStore = ShortcutStore.shared
  @ObservedObject var launchAtLogin: LaunchAtLoginModel
  @ObservedObject var windowController: WindowActivationController
  private let appVersion = AppVersion.current

  var body: some View {
    Button(openMenuTitle) {
      windowController.openCommandPalette()
    }
    Button("Configure") {
      windowController.openConfiguration()
    }
    Toggle(
      "Open at Login",
      isOn: Binding(
        get: { launchAtLogin.isEnabled },
        set: { launchAtLogin.setEnabled($0) }
      )
    )
    Divider()
    Text(appVersion.menuTitle)
    Button("Quit hatch") {
      NSApplication.shared.terminate(nil)
    }
  }

  private var openMenuTitle: String {
    let shortcut = shortcutStore.effectiveOpenHatchShortcut?.displayString ?? "disabled"
    return "Open \(shortcut)"
  }
}

private struct AppVersion {
  let shortVersion: String

  var menuTitle: String {
    "Version \(shortVersion)"
  }

  static let current: AppVersion = {
    let info = Bundle.main.infoDictionary ?? [:]
    let shortVersion =
      (info["CFBundleShortVersionString"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines)

    return AppVersion(
      shortVersion: shortVersion?.isEmpty == false ? shortVersion! : "1.0"
    )
  }()
}

private struct MenuBarLabelView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var windowController: WindowActivationController

  var body: some View {
    Image(nsImage: MenuBarAssets.statusImage)
      .task {
        windowController.setOpenMainWindowAction {
          openWindow(id: "main")
        }
      }
  }
}
