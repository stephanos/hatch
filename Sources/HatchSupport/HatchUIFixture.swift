import Foundation

public enum HatchUIFixtureState: Sendable {
  case unconfigured
  case configured
  case populated
}

public struct HatchUIProjectSeed: Sendable {
  public let name: String
  public let tasks: [String]
  public let defaultRepos: [String]
  public let repoBaseBranches: [String: String]

  public init(
    name: String,
    tasks: [String],
    defaultRepos: [String] = [],
    repoBaseBranches: [String: String] = [:]
  ) {
    self.name = name
    self.tasks = tasks
    self.defaultRepos = defaultRepos
    self.repoBaseBranches = repoBaseBranches
  }
}

public enum HatchUIFixture {
  public static let populatedProjects: [HatchUIProjectSeed] = [
    HatchUIProjectSeed(
      name: "alpha",
      tasks: ["setup-ci", "design-system"],
      defaultRepos: ["api", "web"],
      repoBaseBranches: ["api": "main", "web": "develop"]
    ),
    HatchUIProjectSeed(name: "beta", tasks: ["landing-page"]),
    HatchUIProjectSeed(name: "gamma", tasks: ["ios-shell", "ops-audit", "release-train"]),
    HatchUIProjectSeed(name: "delta", tasks: []),
    HatchUIProjectSeed(name: "epsilon", tasks: ["docs-refresh"]),
    HatchUIProjectSeed(name: "zeta", tasks: []),
    HatchUIProjectSeed(name: "eta", tasks: ["billing-hooks"]),
  ]

  public static func prepare(
    configDir: URL,
    workspaceRoot: URL,
    state: HatchUIFixtureState,
    editor: String = "zed",
    recentProjects: [String] = []
  ) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)

    switch state {
    case .unconfigured:
      return
    case .configured:
      try seedConfiguredState(
        configDir: configDir,
        workspaceRoot: workspaceRoot,
        editor: editor,
        recentProjects: recentProjects
      )
    case .populated:
      try seedConfiguredState(
        configDir: configDir,
        workspaceRoot: workspaceRoot,
        editor: editor,
        recentProjects: recentProjects
      )
      try seedProjects(workspaceRoot: workspaceRoot, projects: populatedProjects)
    }
  }

  public static func seedConfiguredState(
    configDir: URL,
    workspaceRoot: URL,
    editor: String = "zed",
    recentProjects: [String] = []
  ) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: workspaceRoot.appendingPathComponent(".hatch/state", isDirectory: true),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: workspaceRoot.appendingPathComponent("bin", isDirectory: true),
      withIntermediateDirectories: true
    )

    try """
    workspace_root = "\(tomlEscaped(workspaceRoot.path))"
    cli_install_path = "\(tomlEscaped(workspaceRoot.appendingPathComponent("bin").path))"
    """
    .write(to: configDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

    try """
    default_org = "acme"
    default_repos = []
    branch_template = "{user}/{task}"
    editor = "\(tomlEscaped(editor))"
    hooks_include = []
    """
    .write(
      to: workspaceRoot.appendingPathComponent(".hatch/config.toml"),
      atomically: true,
      encoding: .utf8
    )

    if !recentProjects.isEmpty {
      let data = try JSONEncoder().encode(recentProjects)
      try data.write(
        to: workspaceRoot.appendingPathComponent(".hatch/state/recent-projects.json"),
        options: .atomic
      )
    }
  }

  public static func seedProjects(
    workspaceRoot: URL,
    projects: [HatchUIProjectSeed]
  ) throws {
    let fileManager = FileManager.default

    for project in projects {
      let projectDirectory = workspaceRoot.appendingPathComponent(project.name, isDirectory: true)
      try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
      try "".write(
        to: projectDirectory.appendingPathComponent(".project"),
        atomically: true,
        encoding: .utf8
      )

      if !project.defaultRepos.isEmpty || !project.repoBaseBranches.isEmpty {
        let defaultRepos = project.defaultRepos
          .map { "\"\($0)\"" }
          .joined(separator: ", ")
        var lines = ["default_repos = [\(defaultRepos)]"]
        if !project.repoBaseBranches.isEmpty {
          lines.append("[repo_base_branches]")
          for repo in project.repoBaseBranches.keys.sorted() {
            lines.append("\(repo) = \"\(project.repoBaseBranches[repo]!)\"")
          }
        }
        try lines.joined(separator: "\n").appending("\n").write(
          to: projectDirectory.appendingPathComponent("hatch.toml"),
          atomically: true,
          encoding: .utf8
        )
      }

      for task in project.tasks {
        try fileManager.createDirectory(
          at: projectDirectory.appendingPathComponent(task, isDirectory: true),
          withIntermediateDirectories: true
        )
      }
    }
  }

  private static func tomlEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}
