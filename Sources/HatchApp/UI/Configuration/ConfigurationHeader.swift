import SwiftUI

struct ConfigurationHeader: View {
  let mode: ConfigurationScreenMode

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color(red: 0.98, green: 0.91, blue: 0.58))
          .frame(width: 56, height: 56)
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(Color(red: 0.84, green: 0.67, blue: 0.18).opacity(0.45), lineWidth: 1)
          .frame(width: 56, height: 56)
        Image(nsImage: MenuBarAssets.configurationImage)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text(mode.title)
          .font(.system(size: 32, weight: .semibold))
        Text(mode.subtitle)
          .font(.body)
          .foregroundStyle(.secondary)
      }
    }
  }
}
