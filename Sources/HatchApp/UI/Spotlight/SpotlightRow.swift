import SwiftUI

struct SpotlightRow: View {
  let icon: String
  let title: String
  let detail: String
  let trailing: String?
  let onSelect: () -> Void
  var isPrimaryMatch = false

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 10) {
        ZStack {
          Circle()
            .fill(iconBackgroundColor)
            .frame(width: 26, height: 26)
          Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(iconForegroundColor)
        }

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
    .buttonStyle(.plain)
  }

  private var backgroundColor: Color {
    isPrimaryMatch ? Color.white.opacity(0.42) : Color.white.opacity(0.28)
  }

  private var borderColor: Color {
    isPrimaryMatch ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.18)
  }

  private var iconBackgroundColor: Color {
    isPrimaryMatch ? Color.white.opacity(0.95) : Color.white.opacity(0.88)
  }

  private var iconForegroundColor: Color {
    isPrimaryMatch ? .primary : .secondary
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
