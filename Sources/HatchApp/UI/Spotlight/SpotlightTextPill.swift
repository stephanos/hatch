import SwiftUI

struct SpotlightTextPill: View {
  let text: String
  var isPrimaryMatch = false

  var body: some View {
    Text(text)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        Capsule(style: .continuous)
          .fill(isPrimaryMatch ? Color.white.opacity(0.82) : Color.white.opacity(0.7))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(
            isPrimaryMatch ? Color.accentColor.opacity(0.26) : Color.white.opacity(0.85),
            lineWidth: 1
          )
      )
      .shadow(color: isPrimaryMatch ? .black.opacity(0.1) : .clear, radius: 12, y: 6)
      .scaleEffect(isPrimaryMatch ? 1 : 0.98, anchor: .center)
      .opacity(isPrimaryMatch ? 1 : 0.72)
  }
}
