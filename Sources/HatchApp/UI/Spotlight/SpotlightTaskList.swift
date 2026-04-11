import HatchCore
import SwiftUI

struct SpotlightTaskList: View {
  let tasks: [TaskSummary]
  let onSelect: (TaskSummary) -> Void

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
          SpotlightRow(
            icon: "folder",
            title: task.task,
            detail: task.project,
            trailing: nil,
            onSelect: { onSelect(task) },
            isPrimaryMatch: index == 0
          )
        }
      }
    }
  }
}
