import SwiftUI

struct SpotlightCommandList: View {
  private enum Metrics {
    static let maxHeight: CGFloat = 188
  }

  let commands: [SpotlightCommand]
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
    .onPreferenceChange(SpotlightCommandPreviewHeightPreferenceKey.self) { height in
      guard height > 0 else { return }
      withAnimation(.easeInOut(duration: 0.2)) {
        contentHeight = height
      }
    }
  }

  private var content: some View {
    FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
      ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
        SpotlightTextPill(
          text: command.cliTitle,
          isPrimaryMatch: highlightsPrimaryMatch && index == 0
        )
        .accessibilityIdentifier(
          highlightsPrimaryMatch && index == 0
            ? "spotlight-command-primary-\(command.cliTitle.replacingOccurrences(of: " ", with: "-"))"
            : "spotlight-command-\(command.cliTitle.replacingOccurrences(of: " ", with: "-"))"
        )
      }
    }
    .background(
      GeometryReader { geometry in
        Color.clear.preference(
          key: SpotlightCommandPreviewHeightPreferenceKey.self,
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

private struct SpotlightCommandPreviewHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
