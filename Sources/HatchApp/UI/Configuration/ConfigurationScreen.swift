import HatchCore
import SwiftUI

struct ConfigurationScreen: View {
  private let editorDiscovery = EditorDiscovery.current()
  let mode: ConfigurationScreenMode
  @Binding var workspaceRoot: String
  @Binding var cliInstallPath: String
  @Binding var branchTemplate: String
  @Binding var defaultOrg: String
  @Binding var defaultRepos: String
  @Binding var editor: String
  @Binding var hooksInclude: [String]
  let onSubmit: () -> Void
  var onBack: (() -> Void)? = nil
  @State private var hasAppliedRecommendedEditor = false

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider()

      ScrollView {
        VStack(spacing: 0) {
          formCard
        }
        .frame(maxWidth: .infinity, alignment: .top)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

      Divider()

      footer
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .frame(
      width: AppWindowMetrics.configurationWindowWidth,
      height: AppWindowMetrics.configurationWindowHeight
    )
    .accessibilityIdentifier(
      mode == .setup ? "configuration-screen-setup" : "configuration-screen-configure"
    )
    .onAppear {
      applyRecommendedEditorIfNeeded()
    }
  }

  private var header: some View {
    ConfigurationHeader(mode: mode)
      .frame(maxWidth: 940, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.top, 28)
      .padding(.bottom, 24)
      .frame(maxWidth: .infinity, alignment: .center)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var formCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      ConfigurationField(
        title: "Workspace Root",
        prompt: "",
        detail: mode.workspaceRootDetail,
        isRequired: true,
        text: $workspaceRoot,
        isDisabled: !mode.workspaceRootIsEditable
      )
      ConfigurationField(
        title: "CLI Install Path",
        prompt: "",
        detail: mode.cliInstallPathDetail,
        isRequired: true,
        text: $cliInstallPath,
        isDisabled: !mode.cliInstallPathIsEditable
      )
      ConfigurationField(
        title: "Branch Template",
        prompt: "",
        detail:
          "hatch uses this pattern when creating new git branches. `{user}` refers to the configured git user.",
        isRequired: true,
        text: $branchTemplate
      )
      if mode.showsEditorField {
        ConfigurationField(
          title: "Editor",
          prompt: "",
          detail: "Command hatch should use when opening tasks and config files.",
          isRequired: true,
          text: $editor,
          recommendation: editorDiscovery.recommended,
          examples: editorExamples,
          onSelectExample: { editor = $0 }
        )
      }
      ConfigurationField(
        title: "Default GitHub Org",
        prompt: "",
        detail:
          "If you enter a repo without an org, hatch will use this org automatically.",
        isRequired: false,
        text: $defaultOrg
      )
      ConfigurationField(
        title: "Default Repos",
        prompt: "",
        detail:
          "List of repos to always checkout into a new task folder by default. This can be overridden per project.",
        isRequired: false,
        text: $defaultRepos
      )
      BuiltinHooksSection(hooksInclude: $hooksInclude)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .frame(maxWidth: 680, alignment: .leading)
    .padding(.horizontal, 32)
    .padding(.vertical, 28)
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var footer: some View {
    HStack(spacing: 16) {
      if mode.showsBackButton, let onBack {
        Button("Cancel") {
          onBack()
        }
        .accessibilityIdentifier("configuration-cancel")
        .buttonStyle(.plain)
      }

      Spacer()

      Button(mode.actionTitle) {
        onSubmit()
      }
      .accessibilityIdentifier("configuration-submit")
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(
        workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || cliInstallPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || branchTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || editor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      )
    }
    .padding(.horizontal, 32)
    .padding(.vertical, 18)
    .background(.bar)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func applyRecommendedEditorIfNeeded() {
    guard !hasAppliedRecommendedEditor else { return }
    hasAppliedRecommendedEditor = true
    guard editor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard let recommended = editorDiscovery.recommended else { return }
    editor = recommended
  }

  private var editorExamples: [String] {
    guard let recommended = editorDiscovery.recommended else {
      return editorDiscovery.examples
    }
    return editorDiscovery.examples.filter { $0 != recommended }
  }
}
