import Foundation

public struct BuiltinHookOption: Identifiable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let detail: String
  public let effects: [String]

  public init(id: String, title: String, detail: String, effects: [String]) {
    self.id = id
    self.title = title
    self.detail = detail
    self.effects = effects
  }
}

public enum BuiltinHookOptions {
  public static let agentAutoCreate = BuiltinHookOption(
    id: BuiltinHookCatalog.agentAutoCreateInclude,
    title: "Agent Instructions Files",
    detail:
      "Creates shared instruction files for new projects, tasks, and repos so agent tools have a consistent repo-local entry point.",
    effects: [
      "Project: writes AGENTS.md and a CLAUDE.md file that references it.",
      "Task: writes AGENTS.md plus CLAUDE.md and CLAUDE.local.md references.",
      "Repo: writes AGENTS.md and a CLAUDE.md reference inside each added repo.",
    ]
  )

  public static let all = [agentAutoCreate]
}

enum BuiltinHookCatalog {
  static let agentAutoCreateInclude = "builtin:auto-create-agent.md"
  static let legacyClaudeAutoCreateInclude = "builtin:auto-create-claude.md"
  static let legacyUnprefixedClaudeAutoCreateInclude = "auto-create-claude.md"

  static func merged(config: WorkspaceConfig) -> [HookName: HookResolution] {
    var hooks = config.hooks.mapValues(HookResolution.command)
    AgentBuiltinHook.install(into: &hooks, config: config)

    return hooks
  }
}

private protocol BuiltinHookInstaller {
  static func install(into hooks: inout [HookName: HookResolution], config: WorkspaceConfig)
}

private enum AgentBuiltinHook: BuiltinHookInstaller {
  static func install(into hooks: inout [HookName: HookResolution], config: WorkspaceConfig) {
    let includesAgentBuiltin =
      config.hooksInclude.contains(BuiltinHookCatalog.agentAutoCreateInclude)
      || config.hooksInclude.contains(BuiltinHookCatalog.legacyClaudeAutoCreateInclude)
      || config.hooksInclude.contains(BuiltinHookCatalog.legacyUnprefixedClaudeAutoCreateInclude)

    guard includesAgentBuiltin else {
      return
    }

    hooks[.projectPostCreate] =
      hooks[.projectPostCreate] ?? .builtin(.agent(.project), errorPolicy: .fail)
    hooks[.taskPostCreate] =
      hooks[.taskPostCreate] ?? .builtin(.agent(.task), errorPolicy: .fail)
    hooks[.repoPostAdd] =
      hooks[.repoPostAdd] ?? .builtin(.agent(.repo), errorPolicy: .fail)
  }
}

enum BuiltinHookAction {
  case agent(AgentBuiltinTarget)

  func run(context: HookContext) throws {
    switch self {
    case .agent(let target):
      try target.run(context: context)
    }
  }
}

enum AgentBuiltinTarget {
  case project
  case task
  case repo

  func run(context: HookContext) throws {
    switch self {
    case .project:
      guard let projectPath = context.projectPath else { return }
      try writeFiles(
        agentsContent: "## Project Instructions\n",
        claudeFiles: ["CLAUDE.md"],
        in: projectPath
      )
    case .task:
      guard let taskPath = context.taskPath else { return }
      try writeFiles(
        agentsContent: "## Task Instructions\n",
        claudeFiles: ["CLAUDE.md", "CLAUDE.local.md"],
        in: taskPath
      )
    case .repo:
      guard let repoPath = context.repoPath else { return }
      try writeFiles(
        agentsContent: "## Repo Instructions\n",
        claudeFiles: ["CLAUDE.md"],
        in: repoPath
      )
    }
  }

  private func writeFiles(
    agentsContent: String,
    claudeFiles: [String],
    in directory: URL
  ) throws {
    try agentsContent.write(
      to: directory.appendingPathComponent("AGENTS.md"),
      atomically: true,
      encoding: .utf8
    )

    for filename in claudeFiles {
      try "@AGENTS.md\n".write(
        to: directory.appendingPathComponent(filename),
        atomically: true,
        encoding: .utf8
      )
    }
  }
}
