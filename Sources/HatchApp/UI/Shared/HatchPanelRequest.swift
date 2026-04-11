import SwiftUI

struct HatchPanelRequest: Equatable {
  let id = UUID()
  let target: HatchPanelTarget
  let shouldResetState: Bool

  init(target: HatchPanelTarget, shouldResetState: Bool = false) {
    self.target = target
    self.shouldResetState = shouldResetState
  }
}
