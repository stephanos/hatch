import HatchCore
import SwiftUI

struct SpotlightNewTaskView: View {
  private enum Metrics {
    static let maxPreviewHeight: CGFloat = 156
  }

  let isSelectingProject: Bool
  let projectName: String?
  let error: String?
  let preview: TaskCreationPreview?
  @State private var previewContentHeight: CGFloat = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let error, !error.isEmpty {
        Text(error)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if isSelectingProject {
        Text("Choose which project this task belongs to.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if let projectName {
        Text("Choose a short name for the new task in \(projectName).")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if let preview {
        ScrollView {
          measuredPreviewContent(preview)
        }
        .scrollIndicators(usesScrollView ? .visible : .hidden)
        .frame(height: displayedHeight, alignment: .topLeading)
        .padding(.leading, 14)
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: displayedHeight)
        .onPreferenceChange(SpotlightPreviewHeightPreferenceKey.self) { height in
          guard height > 0 else { return }
          withAnimation(.easeInOut(duration: 0.2)) {
            previewContentHeight = height
          }
        }
      }
    }
    .accessibilityIdentifier(
      isSelectingProject ? "spotlight-start-task-pick-project" : "spotlight-create-task"
    )
  }

  @ViewBuilder
  private func previewContent(_ preview: TaskCreationPreview) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      previewRow(label: "Task Folder", value: taskFolderPreviewPath(for: preview))

      if preview.repos.isEmpty {
        previewRow(label: "Repos", value: "No default repos")
      } else {
        ForEach(preview.repos, id: \.name) { repo in
          VStack(alignment: .leading, spacing: 3) {
            previewRow(label: repo.name, value: repo.destination.lastPathComponent)
            Text(branchLine(for: repo))
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .padding(.leading, 12)
              .accessibilityIdentifier("task-preview-branch-\(repo.name)")
          }
        }
      }
    }
    .padding(.top, 19)
  }

  private func measuredPreviewContent(_ preview: TaskCreationPreview) -> some View {
    previewContent(preview)
      .background(
        GeometryReader { geometry in
          Color.clear.preference(
            key: SpotlightPreviewHeightPreferenceKey.self,
            value: geometry.size.height
          )
        }
      )
  }

  private var usesScrollView: Bool {
    previewContentHeight > Metrics.maxPreviewHeight
  }

  private var displayedHeight: CGFloat? {
    guard previewContentHeight > 0 else {
      return nil
    }

    return min(previewContentHeight, Metrics.maxPreviewHeight)
  }

  private func previewRow(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.primary)
      Text(value)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.leading, 12)
        .textSelection(.enabled)
    }
  }

  private func branchLine(for repo: RepoCreationPreview) -> String {
    if let baseBranch = repo.baseBranch, !baseBranch.isEmpty {
      return "creates branch \(repo.branchName) from origin/\(baseBranch)"
    }
    return "creates branch \(repo.branchName)"
  }

  private func taskFolderPreviewPath(for preview: TaskCreationPreview) -> String {
    "\(preview.project)/\(preview.task)"
  }
}

private struct SpotlightPreviewHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
