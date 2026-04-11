import HatchCore
import SwiftUI

struct SpotlightTaskPreviewList: View {
  private enum Metrics {
    static let maxHeight: CGFloat = 188
  }

  let tasks: [TaskSummary]
  let highlightsPrimaryMatch: Bool
  @State private var contentHeight: CGFloat = 0

  var body: some View {
    ScrollView {
      content
    }
    .scrollIndicators(usesScrollView ? .visible : .hidden)
    .frame(height: displayedHeight, alignment: .topLeading)
    .clipped()
    .animation(.easeInOut(duration: 0.2), value: displayedHeight)
    .onPreferenceChange(SpotlightTaskPreviewHeightPreferenceKey.self) { height in
      guard height > 0 else { return }
      withAnimation(.easeInOut(duration: 0.2)) {
        contentHeight = height
      }
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(groupedTasks) { group in
        VStack(alignment: .leading, spacing: 8) {
          Text(group.project)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)

          FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
              SpotlightTextPill(
                text: task.task,
                isPrimaryMatch: highlightsPrimaryMatch && group.project == firstTask?.project
                  && index == 0
              )
              .accessibilityIdentifier(
                highlightsPrimaryMatch && group.project == firstTask?.project && index == 0
                  ? "task-pill-primary-\(group.project)-\(task.task)"
                  : "task-pill-\(group.project)-\(task.task)"
              )
            }
          }
        }
      }
    }
    .background(
      GeometryReader { geometry in
        Color.clear.preference(
          key: SpotlightTaskPreviewHeightPreferenceKey.self,
          value: geometry.size.height
        )
      }
    )
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var displayedHeight: CGFloat? {
    guard contentHeight > 0 else {
      return nil
    }

    return min(contentHeight, Metrics.maxHeight)
  }

  private var usesScrollView: Bool {
    contentHeight > Metrics.maxHeight
  }

  private var firstTask: TaskSummary? {
    tasks.first
  }

  private var groupedTasks: [TaskGroup] {
    var groups: [TaskGroup] = []

    for task in tasks {
      if let lastIndex = groups.indices.last, groups[lastIndex].project == task.project {
        groups[lastIndex].tasks.append(task)
      } else {
        groups.append(TaskGroup(project: task.project, tasks: [task]))
      }
    }

    return groups
  }
}

private struct TaskGroup: Identifiable {
  let project: String
  var tasks: [TaskSummary]

  var id: String { project }
}

private struct SpotlightTaskPreviewHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
