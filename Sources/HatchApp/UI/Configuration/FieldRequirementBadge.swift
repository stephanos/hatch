import SwiftUI

struct FieldRequirementBadge: View {
  let text: String
  let isRequired: Bool

  var body: some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(isRequired ? Color.accentColor : .secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(
            isRequired ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.12)
          )
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(
            isRequired ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.18),
            lineWidth: 1)
      )
      .accessibilityLabel(isRequired ? "Required field" : "Optional field")
  }
}
