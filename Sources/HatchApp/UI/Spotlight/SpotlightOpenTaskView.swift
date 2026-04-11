import SwiftUI

struct SpotlightOpenTaskView: View {
  let error: String?

  var body: some View {
    Group {
      if let error, !error.isEmpty {
        Text(error)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text("Pick a task to resume.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .accessibilityIdentifier("spotlight-resume-task")
  }
}
