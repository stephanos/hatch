import SwiftUI

struct SpotlightCommandPill: View {
  let command: SpotlightCommand

  var body: some View {
    SpotlightTextPill(text: command.cliTitle, isPrimaryMatch: true)
  }
}
