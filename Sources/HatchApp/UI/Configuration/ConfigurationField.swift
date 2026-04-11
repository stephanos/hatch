import AppKit
import SwiftUI

struct ConfigurationField: View {
  let title: String
  let prompt: String
  let detail: String
  let isRequired: Bool
  @Binding var text: String
  var isDisabled = false
  var recommendation: String? = nil
  var examples: [String] = []
  var onSelectExample: ((String) -> Void)? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        FieldRequirementBadge(
          text: isRequired ? "Required" : "Optional", isRequired: isRequired)
      }
      TextField(prompt, text: $text)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier(accessibilityIdentifier)
        .disabled(isDisabled)
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if !suggestions.isEmpty {
        HStack(alignment: .top, spacing: 8) {
          Text("Suggestions:")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)

          FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(suggestions, id: \.self) { example in
              exampleButton(example)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  @ViewBuilder
  private func exampleButton(_ value: String) -> some View {
    Button {
      onSelectExample?(value)
    } label: {
      Text(value)
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          Capsule(style: .continuous)
            .fill(Color(nsColor: .controlAccentColor).opacity(0.08))
        )
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .onHover { isHovering in
      guard !isDisabled else { return }
      if isHovering {
        NSCursor.pointingHand.push()
      } else {
        NSCursor.pop()
      }
    }
  }

  private var suggestions: [String] {
    var values: [String] = []
    if let recommendation, !recommendation.isEmpty {
      values.append(recommendation)
    }
    for example in examples where !values.contains(example) {
      values.append(example)
    }
    return Array(values.prefix(5))
  }

  private var accessibilityIdentifier: String {
    "configuration-"
      + title
      .lowercased()
      .replacingOccurrences(of: " ", with: "-")
      .replacingOccurrences(of: "/", with: "-")
      + "-field"
  }
}
