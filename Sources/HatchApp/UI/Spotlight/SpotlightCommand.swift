import Foundation

enum SpotlightCommand: CaseIterable, Identifiable {
  case newProject
  case newTask
  case openTask
  case configure

  var id: Self { self }

  var cliTitle: String {
    title.lowercased()
  }

  var title: String {
    switch self {
    case .newProject:
      return "Create project"
    case .newTask:
      return "Start task"
    case .openTask:
      return "Resume task"
    case .configure:
      return "Configure hatch"
    }
  }

  var argumentPrompt: String {
    switch self {
    case .newProject:
      return "project-name"
    case .newTask:
      return "task-name"
    case .openTask:
      return "task"
    case .configure:
      return ""
    }
  }

  var detail: String {
    switch self {
    case .newProject:
      return "Create a new workspace project."
    case .newTask:
      return "Start a task inside a project."
    case .openTask:
      return "Resume an existing task."
    case .configure:
      return "Update settings."
    }
  }

  var acceptsArgument: Bool {
    self != .configure
  }

  var icon: String {
    switch self {
    case .newProject:
      return "folder.badge.plus"
    case .newTask:
      return "plus.rectangle.on.folder"
    case .openTask:
      return "arrow.up.right.square"
    case .configure:
      return "gearshape"
    }
  }

  var trailing: String? {
    nil
  }

  func matchScore(for query: String) -> Int? {
    let normalizedQuery = Self.normalize(query)
    guard !normalizedQuery.isEmpty else {
      return sortOrder * 100
    }

    var bestScore: Int?
    for candidate in candidates {
      let normalizedCandidate = Self.normalize(candidate.value)
      guard !normalizedCandidate.isEmpty else {
        continue
      }

      let score: Int?
      if normalizedCandidate == normalizedQuery {
        score = candidate.weight
      } else if normalizedCandidate.hasPrefix(normalizedQuery) {
        score = candidate.weight + normalizedCandidate.count - normalizedQuery.count
      } else if let subsequenceScore = Self.subsequenceScore(
        query: normalizedQuery,
        candidate: normalizedCandidate
      ) {
        score = candidate.weight + 100 + subsequenceScore
      } else {
        score = nil
      }

      if let score {
        bestScore = min(bestScore ?? score, score)
      }
    }

    return bestScore
  }

  private var candidates: [(value: String, weight: Int)] {
    [
      (cliTitle, 0),
      (abbreviation, 20),
      (detail.lowercased(), 50),
    ]
  }

  private var abbreviation: String {
    cliTitle
      .split(separator: " ")
      .compactMap(\.first)
      .map { String($0) }
      .joined()
  }

  private var sortOrder: Int {
    switch self {
    case .newProject:
      return 0
    case .newTask:
      return 1
    case .openTask:
      return 2
    case .configure:
      return 3
    }
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
