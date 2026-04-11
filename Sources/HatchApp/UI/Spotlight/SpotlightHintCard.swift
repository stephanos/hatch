import SwiftUI

struct SpotlightHintCard: View {
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
      Text(detail)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.white.opacity(0.42))
    )
  }
}
