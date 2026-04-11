import Foundation

public struct RepoCreationPreview: Equatable, Sendable {
  public let name: String
  public let destination: URL
  public let cloneURL: String
  public let branchName: String
  public let baseBranch: String?

  public init(
    name: String,
    destination: URL,
    cloneURL: String,
    branchName: String,
    baseBranch: String?
  ) {
    self.name = name
    self.destination = destination
    self.cloneURL = cloneURL
    self.branchName = branchName
    self.baseBranch = baseBranch
  }
}

public struct TaskCreationPreview: Equatable, Sendable {
  public let project: String
  public let task: String
  public let taskDirectory: URL
  public let repos: [RepoCreationPreview]

  public init(
    project: String,
    task: String,
    taskDirectory: URL,
    repos: [RepoCreationPreview]
  ) {
    self.project = project
    self.task = task
    self.taskDirectory = taskDirectory
    self.repos = repos
  }
}
