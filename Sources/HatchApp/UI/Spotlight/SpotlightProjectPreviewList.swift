import HatchCore
import SwiftUI

struct SpotlightProjectPreviewList: View {
  private enum Metrics {
    static let maxHeight: CGFloat = 188
  }

  let projects: [ProjectSummary]
  let highlightsPrimaryMatch: Bool
  @State private var contentHeight: CGFloat = 0

  var body: some View {
    Group {
      if usesScrollView {
        ScrollView {
          content
        }
        .scrollIndicators(.visible)
        .frame(height: Metrics.maxHeight, alignment: .topLeading)
      } else {
        content
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .clipped()
    .animation(.easeInOut(duration: 0.2), value: usesScrollView)
    .onPreferenceChange(SpotlightProjectPreviewHeightPreferenceKey.self) { height in
      guard height > 0 else { return }
      withAnimation(.easeInOut(duration: 0.2)) {
        contentHeight = height
      }
    }
  }

  private var content: some View {
    FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
      ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
        SpotlightTextPill(
          text: project.name,
          isPrimaryMatch: highlightsPrimaryMatch && index == 0
        )
        .accessibilityIdentifier(
          highlightsPrimaryMatch && index == 0
            ? "project-pill-primary-\(project.name)"
            : "project-pill-\(project.name)"
        )
      }
    }
    .background(
      GeometryReader { geometry in
        Color.clear.preference(
          key: SpotlightProjectPreviewHeightPreferenceKey.self,
          value: geometry.size.height
        )
      }
    )
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var usesScrollView: Bool {
    contentHeight > Metrics.maxHeight
  }
}

private struct SpotlightProjectPreviewHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
