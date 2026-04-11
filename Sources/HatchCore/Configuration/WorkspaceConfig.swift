public struct WorkspaceConfig: Codable, Equatable, Sendable {
  public var defaultOrg: String
  public var defaultRepos: [String]
  public var branchTemplate: String
  public var editor: String?
  public var hooksInclude: [String]
  public var hooks: [HookName: HookDefinition]

  public static let `default` = WorkspaceConfig(
    defaultOrg: "",
    defaultRepos: [],
    branchTemplate: "{user}/{task}",
    editor: nil,
    hooksInclude: [],
    hooks: [:]
  )

  public init(
    defaultOrg: String,
    defaultRepos: [String],
    branchTemplate: String,
    editor: String?,
    hooksInclude: [String],
    hooks: [HookName: HookDefinition]
  ) {
    self.defaultOrg = defaultOrg
    self.defaultRepos = defaultRepos
    self.branchTemplate = branchTemplate
    self.editor = editor
    self.hooksInclude = hooksInclude
    self.hooks = hooks
  }
}
