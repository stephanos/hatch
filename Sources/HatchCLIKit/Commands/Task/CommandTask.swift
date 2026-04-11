import Foundation
import HatchCore

extension HatchCLI {
  static func runTask(arguments: [String]) throws {
    guard let subcommand = arguments.first else {
      throw CLIError(
        message: "usage: \(CLIConstants.executableName) task <create|resume|list|clean> ...")
    }

    switch subcommand {
    case "create":
      try createTask(arguments: Array(arguments.dropFirst()))
    case "resume":
      try resumeTask(arguments: Array(arguments.dropFirst()))
    case "list":
      try listTasks(arguments: Array(arguments.dropFirst()))
    case "clean":
      try cleanTasks(arguments: Array(arguments.dropFirst()))
    default:
      throw CLIError(message: "unknown task command '\(subcommand)'")
    }
  }

  private static func createTask(arguments: [String]) throws {
    guard arguments.count == 2 else {
      throw CLIError(
        message: "usage: \(CLIConstants.executableName) task create <project-name> <task-name>")
    }

    let behavior = LiveHatchBehavior()
    let state = try requireConfiguredState(using: behavior)
    let task = try behavior.createTask(
      project: arguments[0],
      task: arguments[1],
      paths: state.paths,
      config: state.workspaceConfig
    )
    print(task.path.path)
  }

  private static func resumeTask(arguments: [String]) throws {
    let behavior = LiveHatchBehavior()
    let state = try requireConfiguredAppState(using: behavior)
    let task = try resolveTaskLookup(arguments: arguments, tasks: state.tasks)
    guard let workspaceConfig = state.workspaceConfig else {
      throw HatchError.message("hatch is not configured")
    }

    try behavior.openTask(task, paths: state.paths, config: workspaceConfig)
    print(task.path.path)
  }

  private static func listTasks(arguments: [String]) throws {
    guard arguments.count <= 1 else {
      throw CLIError(message: "usage: \(CLIConstants.executableName) task list [project-name]")
    }

    let state = try LiveHatchBehavior().loadAppState()
    let tasks =
      if let projectName = arguments.first {
        state.tasks.filter { $0.project == projectName }
      } else {
        state.tasks
      }

    for task in tasks {
      print("\(task.project)/\(task.task)")
    }
  }

  private static func cleanTasks(arguments: [String]) throws {
    let deleteAll = arguments.contains("--yes")
    let positional = arguments.filter { $0 != "--yes" }
    guard positional.isEmpty else {
      throw CLIError(message: "usage: \(CLIConstants.executableName) task clean [--yes]")
    }

    let state = try LiveHatchBehavior().loadAppState()
    let candidates = cleanupCandidates(tasks: state.tasks)

    guard !candidates.isEmpty else {
      print("No tasks with closed or merged PRs found.")
      return
    }

    let selected = try chooseCleanupCandidates(candidates, deleteAll: deleteAll)
    guard !selected.isEmpty else {
      print("No tasks selected.")
      return
    }

    let fileManager = FileManager.default
    var deleted = 0
    for index in selected {
      let candidate = candidates[index]
      var trashed: NSURL?
      try fileManager.trashItem(at: candidate.task.path, resultingItemURL: &trashed)
      print("Moved to Trash: \(candidate.label)")
      deleted += 1
    }
    print("Deleted \(deleted) task(s).")
  }

}

package func resolveTaskLookup(arguments: [String], tasks: [TaskSummary]) throws -> TaskSummary {
  if arguments.count == 1 {
    let query = arguments[0].trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = query.split(separator: "/", maxSplits: 1).map(String.init)
    if parts.count == 2 {
      guard
        let task = tasks.first(where: { $0.project == parts[0] && $0.task == parts[1] })
      else {
        throw HatchError.message("task \(parts[0])/\(parts[1]) does not exist")
      }
      return task
    }

    let matches = tasks.filter { $0.task == query }
    if let task = matches.only {
      return task
    }
    if !matches.isEmpty {
      let options = matches.map { "\($0.project)/\($0.task)" }.sorted().joined(separator: ", ")
      throw HatchError.message("Task name \(query) is ambiguous. Matches: \(options)")
    }

    let fuzzyMatches = fuzzyTaskMatches(for: query, tasks: tasks)
    if let match = fuzzyMatches.only {
      return match.task
    }
    if let best = fuzzyMatches.first, fuzzyMatches.count > 1 {
      let second = fuzzyMatches[1]
      if best.score >= second.score + 4 {
        return best.task
      }
    }
    if !fuzzyMatches.isEmpty {
      let options = fuzzyMatches.prefix(5).map(\.label).joined(separator: ", ")
      throw HatchError.message("No exact task named \(query). Closest matches: \(options)")
    }
    throw HatchError.message("No task matching \(query) exists in any project")
  }

  guard arguments.count == 2 else {
    throw CLIError(
      message: "usage: \(CLIConstants.executableName) task resume <project-name> <task-name>")
  }

  guard
    let task = tasks.first(where: { $0.project == arguments[0] && $0.task == arguments[1] })
  else {
    throw HatchError.message("task \(arguments[0])/\(arguments[1]) does not exist")
  }
  return task
}

package struct FuzzyTaskMatch {
  package let task: TaskSummary
  package let score: Int

  package init(task: TaskSummary, score: Int) {
    self.task = task
    self.score = score
  }

  package var label: String {
    "\(task.project)/\(task.task)"
  }
}

package func fuzzyTaskMatches(for query: String, tasks: [TaskSummary]) -> [FuzzyTaskMatch] {
  let normalizedQuery = query.lowercased()
  guard !normalizedQuery.isEmpty else { return [] }

  return tasks.compactMap { task in
    let taskName = task.task.lowercased()
    let fullName = "\(task.project)/\(task.task)".lowercased()

    let taskScore = fuzzyScore(query: normalizedQuery, candidate: taskName)
    let fullScore = fuzzyScore(query: normalizedQuery, candidate: fullName)
    let score = max(taskScore, fullScore)

    guard score > 0 else { return nil }
    return FuzzyTaskMatch(task: task, score: score)
  }
  .sorted {
    if $0.score != $1.score {
      return $0.score > $1.score
    }
    return $0.label < $1.label
  }
}

package func fuzzyScore(query: String, candidate: String) -> Int {
  if candidate == query {
    return 100
  }
  if candidate.hasPrefix(query) {
    return 80 - max(0, candidate.count - query.count)
  }
  if candidate.contains(query) {
    return 60 - max(0, candidate.count - query.count)
  }
  if let subsequenceScore = subsequenceScore(query: query, candidate: candidate) {
    return subsequenceScore
  }
  return 0
}

package func subsequenceScore(query: String, candidate: String) -> Int? {
  var queryIndex = query.startIndex
  var previousMatch: String.Index?
  var score = 0

  for candidateIndex in candidate.indices {
    guard queryIndex < query.endIndex else { break }
    if candidate[candidateIndex] != query[queryIndex] {
      continue
    }

    score += 5
    if let previousMatch, candidate.index(after: previousMatch) == candidateIndex {
      score += 3
    }
    if candidateIndex == candidate.startIndex
      || candidate[candidate.index(before: candidateIndex)] == "/"
    {
      score += 2
    }

    previousMatch = candidateIndex
    query.formIndex(after: &queryIndex)
  }

  guard queryIndex == query.endIndex else {
    return nil
  }

  return max(1, score - max(0, candidate.count - query.count))
}

package struct CleanupCandidate {
  package let task: TaskSummary
  package let label: String
  package let repoStates: [String]

  package init(task: TaskSummary, label: String, repoStates: [String]) {
    self.task = task
    self.label = label
    self.repoStates = repoStates
  }
}

package func cleanupCandidates(tasks: [TaskSummary], runner: ProcessRunner = ProcessRunner())
  -> [CleanupCandidate]
{
  tasks.compactMap { task in
    let repoDirectories = taskRepoDirectories(for: task)
    let states = repoDirectories.compactMap { repoDirectory -> String? in
      guard
        let branch = try? runner.run(
          "git",
          arguments: ["-C", repoDirectory.path, "rev-parse", "--abbrev-ref", "HEAD"]
        ),
        !branch.isEmpty,
        let state = currentPRState(branch: branch, repoDirectory: repoDirectory, runner: runner),
        state == "CLOSED" || state == "MERGED"
      else {
        return nil
      }
      return "\(repoDirectory.lastPathComponent):\(state)"
    }

    guard !states.isEmpty else { return nil }
    return CleanupCandidate(
      task: task,
      label: "\(task.project)/\(task.task)",
      repoStates: states
    )
  }
  .sorted { $0.label < $1.label }
}

package func taskRepoDirectories(for task: TaskSummary, fileManager: FileManager = .default)
  -> [URL]
{
  guard
    let children = try? fileManager.contentsOfDirectory(
      at: task.path, includingPropertiesForKeys: nil)
  else {
    return []
  }

  return children.filter { candidate in
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return false }
    return fileManager.fileExists(atPath: candidate.appendingPathComponent(".git").path)
  }
}

package func currentPRState(
  branch: String, repoDirectory: URL, runner: ProcessRunner = ProcessRunner()
) -> String? {
  try? runner.run(
    "gh",
    arguments: [
      "pr", "view", branch, "--json", "state", "--jq", ".state",
    ],
    currentDirectory: repoDirectory
  )
}

package func chooseCleanupCandidates(_ candidates: [CleanupCandidate], deleteAll: Bool) throws
  -> [Int]
{
  try chooseCleanupCandidates(
    candidates,
    deleteAll: deleteAll,
    isInteractive: FileHandle.standardInput.isTTY,
    readInput: { readLine() }
  )
}

package func chooseCleanupCandidates(
  _ candidates: [CleanupCandidate],
  deleteAll: Bool,
  isInteractive: Bool,
  readInput: () -> String?
) throws -> [Int] {
  if deleteAll {
    return Array(candidates.indices)
  }

  guard isInteractive else {
    throw HatchError.message("`hatch task clean` requires an interactive terminal or `--yes`")
  }

  print("Tasks with closed or merged PRs:")
  for (index, candidate) in candidates.enumerated() {
    print("\(index + 1). \(candidate.label) [\(candidate.repoStates.joined(separator: ", "))]")
  }
  print("Enter task numbers to delete, separated by spaces or commas. Press return to cancel.")

  guard let line = readInput(), !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    return []
  }

  let selections =
    line
    .split(whereSeparator: { $0 == " " || $0 == "," })
    .compactMap { Int($0) }
    .map { $0 - 1 }

  let uniqueSelections = Array(Set(selections)).sorted()
  guard uniqueSelections.allSatisfy({ candidates.indices.contains($0) }) else {
    throw HatchError.message("Invalid task selection")
  }
  return uniqueSelections
}

extension Array {
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}
