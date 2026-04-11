import SwiftUI

struct SpotlightPreviewRow: View {
  let title: String
  let detail: String
  let trailing: String?
  var isPrimaryMatch = false

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(titleColor)
        Text(detail)
          .font(.system(size: 12))
          .foregroundStyle(detailColor)
      }

      Spacer()

      if let trailing {
        Text(trailing)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(detailColor)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(backgroundColor)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(borderColor, lineWidth: 1)
    )
    .shadow(color: shadowColor, radius: 16, y: 8)
    .scaleEffect(isPrimaryMatch ? 1 : 0.985, anchor: .center)
    .opacity(isPrimaryMatch ? 1 : 0.76)
  }

  private var backgroundColor: Color {
    isPrimaryMatch ? Color.white.opacity(0.42) : Color.white.opacity(0.28)
  }

  private var borderColor: Color {
    isPrimaryMatch ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.18)
  }

  private var titleColor: Color {
    .primary
  }

  private var detailColor: Color {
    .secondary
  }

  private var shadowColor: Color {
    isPrimaryMatch ? .black.opacity(0.12) : .clear
  }
}
