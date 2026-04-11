import HatchCore
import SwiftUI

struct SpotlightNewProjectView: View {
  private enum Metrics {
    static let maxPreviewHeight: CGFloat = 156
  }

  @Binding var name: String
  let error: String?
  let preview: ProjectCreationPreview?
  @State private var previewContentHeight: CGFloat = 0
  @State private var showsPreview = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let error, !error.isEmpty {
        Text(error)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text("Choose a short name for the new project folder.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      ScrollView {
        if let preview {
          measuredPreviewContent(preview)
        }
      }
      .scrollIndicators(usesScrollView ? .visible : .hidden)
      .frame(height: displayedHeight, alignment: .topLeading)
      .padding(.leading, 14)
      .clipped()
      .animation(.easeInOut(duration: 0.2), value: displayedHeight)
      .onPreferenceChange(SpotlightProjectCreationPreviewHeightPreferenceKey.self) { height in
        guard height > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
          previewContentHeight = height
          showsPreview = true
        }
      }
      .onChange(of: preview?.project) { _, newProject in
        if newProject == nil {
          withAnimation(.easeInOut(duration: 0.2)) {
            showsPreview = false
            previewContentHeight = 0
          }
        }
      }
    }
    .accessibilityIdentifier("spotlight-create-project")
  }

  private func previewContent(_ preview: ProjectCreationPreview) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      previewRow(label: "Project Folder", value: preview.project)
      previewRow(label: "Config File", value: "\(preview.project)/hatch.toml")
    }
    .padding(.top, 19)
  }

  private func measuredPreviewContent(_ preview: ProjectCreationPreview) -> some View {
    previewContent(preview)
      .background(
        GeometryReader { geometry in
          Color.clear.preference(
            key: SpotlightProjectCreationPreviewHeightPreferenceKey.self,
            value: geometry.size.height
          )
        }
      )
  }

  private var usesScrollView: Bool {
    previewContentHeight > Metrics.maxPreviewHeight
  }

  private var displayedHeight: CGFloat? {
    guard showsPreview else { return 0 }
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
}

private struct SpotlightProjectCreationPreviewHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
