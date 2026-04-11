import Foundation
import TOMLDecoder

package enum TOMLCodec {
  package static func decodeBootstrap(from data: Data) throws -> BootstrapConfig {
    try TOMLDecoder().decode(BootstrapTOML.self, from: data).model
  }

  package static func encode(_ config: BootstrapConfig) -> Data {
    var encoder = TOMLEncoder()
    encoder.writeString("workspace_root", value: config.workspaceRoot)
    encoder.writeString("cli_install_path", value: config.cliInstallPath)
    return encoder.data()
  }

  package static func decodeWorkspace(from data: Data) throws -> WorkspaceConfig {
    try TOMLDecoder().decode(WorkspaceTOML.self, from: data).model
  }

  package static func encode(_ config: WorkspaceConfig) -> Data {
    var encoder = TOMLEncoder()
    encoder.writeString("default_org", value: config.defaultOrg)
    encoder.writeArray("default_repos", values: config.defaultRepos)
    encoder.writeString("branch_template", value: config.branchTemplate)
    encoder.writeOptionalString("editor", value: config.editor)
    encoder.writeArray("hooks_include", values: config.hooksInclude)

    for hookName in config.hooks.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let hook = config.hooks[hookName] else { continue }
      encoder.beginTable(["hooks", hookName.rawValue])
      encoder.writeArray("command", values: hook.command)
      encoder.writeString("on_error", value: hook.onError.rawValue)
    }

    return encoder.data()
  }

  package static func decodeProject(from data: Data) throws -> ProjectConfig {
    try TOMLDecoder().decode(ProjectTOML.self, from: data).model
  }

  package static func encode(_ config: ProjectConfig) -> Data {
    var encoder = TOMLEncoder()
    encoder.writeArray("default_repos", values: config.defaultRepos)
    if !config.repoBaseBranches.isEmpty {
      encoder.beginTable(["repo_base_branches"])
      for key in config.repoBaseBranches.keys.sorted() {
        guard let value = config.repoBaseBranches[key] else { continue }
        encoder.writeString(key, value: value)
      }
    }
    return encoder.data()
  }
}

private struct BootstrapTOML: Decodable {
  let workspaceRoot: String
  let cliInstallPath: String?

  var model: BootstrapConfig {
    BootstrapConfig(
      workspaceRoot: workspaceRoot,
      cliInstallPath: cliInstallPath ?? "~/.local/bin"
    )
  }

  enum CodingKeys: String, CodingKey {
    case workspaceRoot = "workspace_root"
    case cliInstallPath = "cli_install_path"
  }
}

private struct WorkspaceTOML: Decodable {
  let defaultOrg: String
  let defaultRepos: [String]
  let branchTemplate: String
  let editor: String?
  let hooksInclude: [String]
  let hooks: [String: HookDefinitionTOML]?

  var model: WorkspaceConfig {
    get throws {
      let mappedHooks = try (hooks ?? [:]).reduce(into: [HookName: HookDefinition]()) {
        partialResult,
        entry in
        guard let name = HookName(rawValue: entry.key) else {
          throw HatchError.message("Unknown hook name in config: \(entry.key)")
        }
        partialResult[name] = entry.value.model
      }

      return WorkspaceConfig(
        defaultOrg: defaultOrg,
        defaultRepos: defaultRepos,
        branchTemplate: branchTemplate,
        editor: editor,
        hooksInclude: hooksInclude,
        hooks: mappedHooks
      )
    }
  }

  enum CodingKeys: String, CodingKey {
    case defaultOrg = "default_org"
    case defaultRepos = "default_repos"
    case branchTemplate = "branch_template"
    case editor
    case hooksInclude = "hooks_include"
    case hooks
  }
}

private struct HookDefinitionTOML: Decodable {
  let command: [String]
  let onError: HookErrorPolicy

  var model: HookDefinition {
    HookDefinition(command: command, onError: onError)
  }

  enum CodingKeys: String, CodingKey {
    case command
    case onError = "on_error"
  }
}

private struct ProjectTOML: Decodable {
  let defaultRepos: [String]
  let repoBaseBranches: [String: String]?

  var model: ProjectConfig {
    ProjectConfig(
      defaultRepos: defaultRepos,
      repoBaseBranches: repoBaseBranches ?? [:]
    )
  }

  enum CodingKeys: String, CodingKey {
    case defaultRepos = "default_repos"
    case repoBaseBranches = "repo_base_branches"
  }
}

private struct TOMLEncoder {
  private var lines: [String] = []

  mutating func writeString(_ key: String, value: String) {
    lines.append("\(quotedKey(key)) = \(quoted(value))")
  }

  mutating func writeOptionalString(_ key: String, value: String?) {
    guard let value else { return }
    writeString(key, value: value)
  }

  mutating func writeArray(_ key: String, values: [String]) {
    let rendered = values.map(quoted).joined(separator: ", ")
    lines.append("\(quotedKey(key)) = [\(rendered)]")
  }

  mutating func beginTable(_ path: [String]) {
    if !lines.isEmpty, lines.last != "" {
      lines.append("")
    }
    lines.append("[\(path.map(quotedKey).joined(separator: "."))]")
  }

  func data() -> Data {
    (lines + [""]).joined(separator: "\n").data(using: .utf8) ?? Data()
  }

  private func quoted(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\t", with: "\\t")
    return "\"\(escaped)\""
  }

  private func quotedKey(_ value: String) -> String {
    let safe = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    if value.unicodeScalars.allSatisfy(safe.contains) {
      return value
    }
    return quoted(value)
  }
}
