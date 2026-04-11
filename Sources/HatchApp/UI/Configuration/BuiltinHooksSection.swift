import HatchCore
import SwiftUI

struct BuiltinHooksSection: View {
  @Binding var hooksInclude: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("Built-in Hooks")
          .font(.subheadline.weight(.semibold))
        FieldRequirementBadge(text: "Optional", isRequired: false)
      }

      Text(
        "Choose which built-in automations hatch should enable for this workspace."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 12) {
        ForEach(BuiltinHookOptions.all) { option in
          BuiltinHookOptionRow(
            option: option,
            isEnabled: binding(for: option.id)
          )
        }
      }
    }
  }

  private func binding(for includeToken: String) -> Binding<Bool> {
    Binding(
      get: { hooksInclude.contains(includeToken) },
      set: { isEnabled in
        if isEnabled {
          if !hooksInclude.contains(includeToken) {
            hooksInclude.append(includeToken)
          }
        } else {
          hooksInclude.removeAll { $0 == includeToken }
        }
      }
    )
  }
}

private struct BuiltinHookOptionRow: View {
  let option: BuiltinHookOption
  @Binding var isEnabled: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(isOn: $isEnabled) {
        VStack(alignment: .leading, spacing: 4) {
          Text(option.title)
            .font(.subheadline.weight(.medium))
          Text(option.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .toggleStyle(.checkbox)

      VStack(alignment: .leading, spacing: 4) {
        ForEach(option.effects, id: \.self) { effect in
          Text(effect)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.leading, 22)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }
}
