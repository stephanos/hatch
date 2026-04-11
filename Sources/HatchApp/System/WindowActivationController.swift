import AppKit
import CoreGraphics
import HatchAppState
import SwiftUI

@MainActor
enum MainWindowPresentation {
  case palette
  case configure
}

@MainActor
final class WindowActivationController: ObservableObject {
  private static let stateResetInterval: TimeInterval = 60
  private static let paletteVerticalOffset: CGFloat = 36
  private static let paletteCornerRadius: CGFloat = 28

  private weak var mainWindow: NSWindow?
  private var openMainWindowAction: (() -> Void)?
  private var openCommandPaletteAction: ((Bool) -> Void)?
  private var openConfigurationAction: ((Bool) -> Void)?
  private var windowResignObserver: NSObjectProtocol?
  private var applicationResignObserver: NSObjectProtocol?
  private var outsideClickMonitor: Any?
  private var lastMainWindowDismissedAt: Date?
  private var pendingPanelRequest: HatchPanelRequest?
  private var dismissesOnResign: Bool
  private var presentation: MainWindowPresentation = .palette
  private var shouldCenterWindowOnNextAttach = false
  private var isOpeningMainWindow = false
  private var paletteTopLeftAnchor: NSPoint?
  private var isRedispatchingOutsideClick = false

  init(dismissesOnResign: Bool = true) {
    self.dismissesOnResign = dismissesOnResign
  }

  func attachMainWindow(_ window: NSWindow?) {
    guard let window else {
      removeWindowObserver()
      mainWindow = nil
      return
    }
    guard mainWindow !== window else {
      return
    }

    isOpeningMainWindow = false
    mainWindow = window
    if window.identifier == nil {
      window.identifier = NSUserInterfaceItemIdentifier("main")
    }
    configure(window: window)
  }

  func setOpenMainWindowAction(_ action: @escaping () -> Void) {
    openMainWindowAction = action
  }

  func setOpenCommandPaletteAction(_ action: @escaping (Bool) -> Void) {
    openCommandPaletteAction = action
  }

  func setOpenConfigurationAction(_ action: @escaping (Bool) -> Void) {
    openConfigurationAction = action
  }

  func openMainWindow() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    if let window = resolvedMainWindow {
      mainWindow = window
      show(window: window)
      return
    }
    requestMainWindowOpenIfNeeded()
  }

  func openCommandPalette() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    let shouldResetState = shouldResetStateOnOpen
    if let window = resolvedMainWindow, openCommandPaletteAction != nil {
      mainWindow = window
      centerWindowOnMainDisplay(window)
      show(window: window)
      openCommandPaletteAction?(shouldResetState)
    } else {
      pendingPanelRequest = HatchPanelRequest(
        target: .commands,
        shouldResetState: shouldResetState
      )
      shouldCenterWindowOnNextAttach = true
      requestMainWindowOpenIfNeeded()
    }
  }

  func openConfiguration() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    let shouldResetState = shouldResetStateOnOpen
    if let window = resolvedMainWindow, openConfigurationAction != nil {
      mainWindow = window
      centerWindowOnMainDisplay(window)
      show(window: window)
      openConfigurationAction?(shouldResetState)
    } else {
      pendingPanelRequest = HatchPanelRequest(
        target: .configure,
        shouldResetState: shouldResetState
      )
      shouldCenterWindowOnNextAttach = true
      requestMainWindowOpenIfNeeded()
    }
  }

  func consumePendingPanelRequest() -> HatchPanelRequest? {
    defer { pendingPanelRequest = nil }
    return pendingPanelRequest
  }

  func setDismissesOnResign(_ dismissesOnResign: Bool) {
    self.dismissesOnResign = dismissesOnResign
  }

  func centerMainWindow() {
    if let mainWindow {
      centerWindowOnMainDisplay(mainWindow)
    } else {
      shouldCenterWindowOnNextAttach = true
    }
  }

  func setPresentation(_ presentation: MainWindowPresentation) {
    self.presentation = presentation
    if presentation != .palette {
      paletteTopLeftAnchor = nil
    }
    if let mainWindow {
      applyPresentation(to: mainWindow)
    }
  }

  func dismissMainWindow() {
    lastMainWindowDismissedAt = Date()
    mainWindow?.orderOut(nil)
  }

  func resizePaletteWindow(height: CGFloat, animated: Bool = true) {
    guard
      presentation == .palette,
      let window = resolvedMainWindow,
      height > 0
    else {
      return
    }

    applyPresentation(to: window)

    let clampedHeight = min(height, AppWindowMetrics.spotlightMaxWindowHeight)
    let targetSize = CGSize(width: AppWindowMetrics.spotlightPanelWidth, height: clampedHeight)
    let contentRect = window.contentRect(forFrameRect: window.frame)
    let heightDelta = targetSize.height - contentRect.height
    let widthDelta = targetSize.width - contentRect.width

    guard abs(heightDelta) > 0.5 || abs(widthDelta) > 0.5 else {
      return
    }

    let topLeftAnchor =
      paletteTopLeftAnchor
      ?? NSPoint(x: window.frame.minX, y: window.frame.maxY)
    var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: targetSize))
    frame.origin.x = topLeftAnchor.x
    frame.origin.y = topLeftAnchor.y - frame.height

    if animated, window.isVisible {
      window.setFrame(frame, display: true, animate: true)
    } else {
      window.setFrame(frame, display: true)
    }

    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window, self.presentation == .palette else { return }
      self.applyPresentation(to: window)
    }
  }

  private func configure(window: NSWindow) {
    removeWindowObserver()
    applyPresentation(to: window)
    if shouldCenterWindowOnNextAttach {
      centerWindowOnMainDisplay(window)
      shouldCenterWindowOnNextAttach = false
    }
    window.collectionBehavior.insert(.moveToActiveSpace)
    window.collectionBehavior.insert(.fullScreenAuxiliary)
    window.animationBehavior = .utilityWindow
    installOutsideClickMonitor(for: window)

    windowResignObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.dismissesOnResign else {
          return
        }
        self.dismissMainWindow()
      }
    }

    applicationResignObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApplication.shared,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard
          let self,
          self.dismissesOnResign,
          self.presentation == .palette
        else {
          return
        }
        self.dismissMainWindow()
      }
    }
  }

  private func applyPresentation(to window: NSWindow) {
    window.toolbar = nil

    switch presentation {
    case .palette:
      window.styleMask = [.titled, .fullSizeContentView]
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.isMovable = false
      window.isMovableByWindowBackground = false
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = false
      window.level = .floating
      hideTrafficLights(in: window)
    case .configure:
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = false
      window.isMovable = true
      window.isMovableByWindowBackground = false
      window.isOpaque = true
      window.backgroundColor = NSColor.windowBackgroundColor
      window.hasShadow = true
      window.level = .normal
      showTrafficLights(in: window)
    }
  }

  private func hideTrafficLights(in window: NSWindow) {
    let containerViews = Set(trafficLightButtons(in: window).compactMap(\.superview))
    for container in containerViews {
      container.isHidden = true
      container.alphaValue = 0
    }
    for button in trafficLightButtons(in: window) {
      button.isHidden = true
      button.alphaValue = 0
      button.isEnabled = false
    }
  }

  private func showTrafficLights(in window: NSWindow) {
    let containerViews = Set(trafficLightButtons(in: window).compactMap(\.superview))
    for container in containerViews {
      container.isHidden = false
      container.alphaValue = 1
    }
    for button in trafficLightButtons(in: window) {
      button.isHidden = false
      button.alphaValue = 1
      button.isEnabled = true
    }
  }

  private func trafficLightButtons(in window: NSWindow) -> [NSButton] {
    [
      window.standardWindowButton(.closeButton),
      window.standardWindowButton(.miniaturizeButton),
      window.standardWindowButton(.zoomButton),
    ]
    .compactMap { $0 }
  }

  private func installOutsideClickMonitor(for window: NSWindow) {
    removeOutsideClickMonitor()
    let eventTypes: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
    outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
      matching: eventTypes
    ) { [weak self, weak window] event in
      guard
        let self,
        let window,
        let contentView = window.contentView,
        self.dismissesOnResign,
        self.presentation == .palette,
        window.isVisible
      else {
        return event
      }
      guard !self.isRedispatchingOutsideClick else {
        self.isRedispatchingOutsideClick = false
        return event
      }

      let location = event.locationInWindow
      guard !self.paletteHitPath(in: contentView.bounds).contains(location) else {
        return event
      }

      self.dismissMainWindow()
      self.redispatch(event)
      return nil
    }
  }

  private func paletteHitPath(in bounds: CGRect) -> NSBezierPath {
    NSBezierPath(
      roundedRect: bounds,
      xRadius: Self.paletteCornerRadius,
      yRadius: Self.paletteCornerRadius
    )
  }

  private func redispatch(_ event: NSEvent) {
    guard let cgEvent = event.cgEvent?.copy() else {
      return
    }
    isRedispatchingOutsideClick = true
    cgEvent.post(tap: CGEventTapLocation.cghidEventTap)
  }

  private func centerWindowOnMainDisplay(_ window: NSWindow) {
    let visibleFrame =
      preferredTargetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
    let verticalOffset = presentation == .palette ? Self.paletteVerticalOffset : 0
    let origin = NSPoint(
      x: visibleFrame.midX - (window.frame.width / 2),
      y: visibleFrame.midY - (window.frame.height / 2) + verticalOffset
    )
    window.setFrameOrigin(origin)
    if presentation == .palette {
      paletteTopLeftAnchor = NSPoint(x: window.frame.minX, y: window.frame.maxY)
    }
  }

  private var preferredTargetScreen: NSScreen? {
    frontmostWindowScreen ?? screenContainingMouseLocation ?? mainDisplayScreen
  }

  private var screenContainingMouseLocation: NSScreen? {
    let location = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(location) }
  }

  private var mainDisplayScreen: NSScreen? {
    let displayID = CGMainDisplayID()
    return NSScreen.screens.first { screen in
      guard
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber
      else {
        return false
      }
      return CGDirectDisplayID(screenNumber.uint32Value) == displayID
    }
  }

  private var frontmostWindowScreen: NSScreen? {
    guard let application = NSWorkspace.shared.frontmostApplication else {
      return nil
    }

    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard
      let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else {
      return nil
    }

    for window in windows {
      guard
        windowOwnerPID(window) == application.processIdentifier,
        windowLayer(window) == 0,
        windowAlpha(window) > 0,
        let bounds = windowBounds(window)
      else {
        continue
      }

      if let matchingScreen = screen(containingQuartzBounds: bounds) {
        return matchingScreen
      }
    }

    return nil
  }

  private func screen(containingQuartzBounds bounds: CGRect) -> NSScreen? {
    let appKitBounds = CGRect(
      x: bounds.origin.x,
      y: mainDisplayTopEdge - bounds.origin.y - bounds.height,
      width: bounds.width,
      height: bounds.height
    )

    return NSScreen.screens.max { lhs, rhs in
      intersectionArea(lhs.frame, appKitBounds) < intersectionArea(rhs.frame, appKitBounds)
    }
  }

  private var mainDisplayTopEdge: CGFloat {
    mainDisplayScreen?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
  }

  private func windowOwnerPID(_ window: [String: Any]) -> pid_t? {
    window[kCGWindowOwnerPID as String] as? pid_t
  }

  private func windowLayer(_ window: [String: Any]) -> Int {
    window[kCGWindowLayer as String] as? Int ?? 0
  }

  private func windowAlpha(_ window: [String: Any]) -> Double {
    window[kCGWindowAlpha as String] as? Double ?? 0
  }

  private func windowBounds(_ window: [String: Any]) -> CGRect? {
    guard
      let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
      let bounds = CGRect(dictionaryRepresentation: dictionary)
    else {
      return nil
    }

    guard bounds.width > 0, bounds.height > 0 else {
      return nil
    }

    return bounds
  }

  private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull else {
      return 0
    }
    return intersection.width * intersection.height
  }

  private func show(window: NSWindow) {
    applyPresentation(to: window)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window else { return }
      self.applyPresentation(to: window)
    }
  }

  private var shouldResetStateOnOpen: Bool {
    guard let lastMainWindowDismissedAt else {
      return false
    }
    return Date().timeIntervalSince(lastMainWindowDismissedAt) > Self.stateResetInterval
  }

  private func removeWindowObserver() {
    if let windowResignObserver {
      NotificationCenter.default.removeObserver(windowResignObserver)
      self.windowResignObserver = nil
    }
    if let applicationResignObserver {
      NotificationCenter.default.removeObserver(applicationResignObserver)
      self.applicationResignObserver = nil
    }
    removeOutsideClickMonitor()
  }

  private func removeOutsideClickMonitor() {
    if let outsideClickMonitor {
      NSEvent.removeMonitor(outsideClickMonitor)
      self.outsideClickMonitor = nil
    }
  }

  private var resolvedMainWindow: NSWindow? {
    if let mainWindow {
      return mainWindow
    }

    return NSApplication.shared.windows.first { window in
      window.identifier?.rawValue == "main"
    }
  }

  private func requestMainWindowOpenIfNeeded() {
    guard !isOpeningMainWindow else {
      return
    }

    isOpeningMainWindow = true
    openMainWindowAction?()
  }
}

struct MainWindowRootView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var model: AppModel
  @ObservedObject var windowController: WindowActivationController

  var body: some View {
    ContentView(model: model, windowController: windowController)
      .background(MainWindowAccessor(windowController: windowController))
      .task {
        windowController.setOpenMainWindowAction {
          openWindow(id: "main")
        }
      }
  }
}

private struct MainWindowAccessor: NSViewRepresentable {
  let windowController: WindowActivationController

  func makeNSView(context: Context) -> WindowObservationView {
    let view = WindowObservationView()
    view.onWindowChange = { window in
      windowController.attachMainWindow(window)
    }
    return view
  }

  func updateNSView(_ nsView: WindowObservationView, context: Context) {
    nsView.onWindowChange = { window in
      windowController.attachMainWindow(window)
    }
    windowController.attachMainWindow(nsView.window)
  }
}

private final class WindowObservationView: NSView {
  var onWindowChange: ((NSWindow?) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onWindowChange?(window)
  }
}
