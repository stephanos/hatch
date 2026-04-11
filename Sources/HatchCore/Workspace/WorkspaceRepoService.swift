import Foundation

struct WorkspaceRepoService {
  let runner: ProcessRunner

  func resolveRepoSpec(
    repoInput: String,
    defaultOrg: String
  ) throws -> (repo: String, cloneURL: String) {
    let trimmed = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw HatchError.message("repo cannot be empty")
    }
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("git@") {
      let cloneURL = String(
        trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
      return (deriveRepoName(from: cloneURL), cloneURL)
    }
    return (trimmed, "https://github.com/\(defaultOrg)/\(trimmed).git")
  }

  func checkoutTaskBranch(at repoPath: URL, branch: String, baseBranch: String?) throws {
    if try remoteBranchExists(repoPath: repoPath, branch: branch) {
      try runner.run(
        "git",
        arguments: ["-C", repoPath.path, "checkout", "-b", branch, "origin/\(branch)"]
      )
      return
    }

    var args = ["-C", repoPath.path, "checkout", "-b", branch]
    if let baseBranch, !baseBranch.isEmpty {
      guard try remoteBranchExists(repoPath: repoPath, branch: baseBranch) else {
        throw HatchError.message(
          "Configured base branch \(baseBranch) does not exist on origin for \(repoPath.lastPathComponent)"
        )
      }
      args.append("origin/\(baseBranch)")
    }
    try runner.run("git", arguments: args)
  }

  func renderTemplate(_ template: String, values: [String: String]) -> String {
    var result = template
    for (key, value) in values {
      result = result.replacingOccurrences(of: "{\(key)}", with: value)
    }
    return result
  }

  private func deriveRepoName(from url: String) -> String {
    let trimmed = url.replacingOccurrences(of: ".git", with: "")
    let pieces = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" })
    return pieces.last.map(String.init) ?? trimmed
  }

  private func remoteBranchExists(repoPath: URL, branch: String) throws -> Bool {
    do {
      _ = try runner.run(
        "git",
        arguments: [
          "-C", repoPath.path, "show-ref", "--verify", "--quiet", "refs/remotes/origin/\(branch)",
        ]
      )
      return true
    } catch {
      return false
    }
  }
}
