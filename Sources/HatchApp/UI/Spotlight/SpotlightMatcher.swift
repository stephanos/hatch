import Foundation
import HatchCore

enum SpotlightMatcher {
  static func matchingCommands(query: String) -> [SpotlightCommand] {
    SpotlightCommand.allCases
      .compactMap { command in
        command.matchScore(for: query).map { (command, $0) }
      }
      .sorted { lhs, rhs in
        if lhs.1 == rhs.1 {
          return lhs.0.cliTitle < rhs.0.cliTitle
        }
        return lhs.1 < rhs.1
      }
      .map(\.0)
  }

  static func matchingProjects(query: String, projects: [ProjectSummary]) -> [ProjectSummary] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return projects.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
    }

    return
      projects
      .compactMap { project in
        matchScore(candidate: project.name, query: trimmed).map { (project, $0) }
      }
      .sorted { lhs, rhs in
        if lhs.1 == rhs.1 {
          return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }
        return lhs.1 < rhs.1
      }
      .map(\.0)
  }

  static func filteredTasks(
    query: String,
    tasks: [TaskSummary],
    recentProjects: [String]
  ) -> [TaskSummary] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return tasks.sorted(by: taskSort(recentProjects: recentProjects))
    }

    return
      tasks
      .compactMap { task in
        taskMatch(task: task, query: trimmed).map { (task, $0) }
      }
      .sorted { lhs, rhs in
        if lhs.1 == rhs.1 {
          return taskSort(recentProjects: recentProjects)(lhs.0, rhs.0)
        }
        return lhs.1 < rhs.1
      }
      .map(\.0)
  }

  private static func taskMatch(task: TaskSummary, query: String) -> Int? {
    let directCandidates = ["\(task.project)/\(task.task)", task.task]
    let directScore = directCandidates.compactMap { matchScore(candidate: $0, query: query) }.min()
    let projectScore = matchScore(candidate: task.project, query: query)

    switch (directScore, projectScore) {
    case (.some(let directScore), .some(let projectScore)):
      return min(directScore, projectScore)
    case (.some(let directScore), nil):
      return directScore
    case (nil, .some(let projectScore)):
      return projectScore
    case (nil, nil):
      return nil
    }
  }

  private static func taskSort(recentProjects: [String]) -> (TaskSummary, TaskSummary) -> Bool {
    { lhs, rhs in
      let lhsProjectRank = recentProjects.firstIndex(of: lhs.project) ?? Int.max
      let rhsProjectRank = recentProjects.firstIndex(of: rhs.project) ?? Int.max

      if lhsProjectRank != rhsProjectRank {
        return lhsProjectRank < rhsProjectRank
      }

      if lhs.project != rhs.project {
        return lhs.project.localizedCaseInsensitiveCompare(rhs.project) == .orderedAscending
      }

      return lhs.task.localizedCaseInsensitiveCompare(rhs.task) == .orderedAscending
    }
  }

  private static func matchScore(candidate: String, query: String) -> Int? {
    let normalizedQuery = normalize(query)
    let normalizedCandidate = normalize(candidate)

    guard !normalizedQuery.isEmpty else {
      return 0
    }
    if normalizedCandidate == normalizedQuery {
      return 0
    }
    if normalizedCandidate.hasPrefix(normalizedQuery) {
      return normalizedCandidate.count - normalizedQuery.count
    }
    guard
      let subsequenceScore = subsequenceScore(
        query: normalizedQuery, candidate: normalizedCandidate)
    else {
      return nil
    }
    return 100 + subsequenceScore
  }

  private static func normalize(_ value: String) -> String {
    value
      .lowercased()
      .unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) }
      .map(String.init)
      .joined()
  }

  private static func subsequenceScore(query: String, candidate: String) -> Int? {
    var candidateIndex = candidate.startIndex
    var score = 0

    for queryCharacter in query {
      guard let matchIndex = candidate[candidateIndex...].firstIndex(of: queryCharacter) else {
        return nil
      }
      score += candidate.distance(from: candidateIndex, to: matchIndex)
      candidate.formIndex(after: &candidateIndex)
    }

    return score
  }
}
