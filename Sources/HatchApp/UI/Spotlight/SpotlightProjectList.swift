import HatchCore
import SwiftUI

struct SpotlightProjectList: View {
  let projects: [ProjectSummary]
  let onSelect: (ProjectSummary) -> Void

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        ForEach(projects) { project in
          SpotlightRow(
            icon: "doc.text",
            title: project.name,
            detail: "Open project config",
            trailing: nil,
            onSelect: { onSelect(project) }
          )
        }
      }
    }
  }
}
