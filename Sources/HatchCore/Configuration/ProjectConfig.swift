public struct ProjectConfig: Codable, Equatable, Sendable {
  public var defaultRepos: [String]
  public var repoBaseBranches: [String: String]

  public static let `default` = ProjectConfig(defaultRepos: [], repoBaseBranches: [:])

  public init(defaultRepos: [String], repoBaseBranches: [String: String]) {
    self.defaultRepos = defaultRepos
    self.repoBaseBranches = repoBaseBranches
  }
}
