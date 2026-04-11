import AppKit
import Foundation

struct WorkspacePathOpener {
  let runner: ProcessRunner

  func openPath(_ path: URL, editor: String?) throws {
    let trimmed = editor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else {
      NSWorkspace.shared.open(path)
      return
    }

    let parts = try parseCommandLine(trimmed)
    let program = parts[0]
    try runner.run(program, arguments: Array(parts.dropFirst()) + [path.path])
  }

  func openTaskPath(_ path: URL, editor: String?) throws {
    let trimmed = editor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else {
      throw HatchError.message("Choose an editor in Setup or Configure before opening tasks.")
    }

    let parts = try parseCommandLine(trimmed)
    let program = parts[0]
    try runner.run(program, arguments: Array(parts.dropFirst()) + [path.path])
  }

  private func parseCommandLine(_ commandLine: String) throws -> [String] {
    enum QuoteState {
      case unquoted
      case single
      case double
    }

    var tokens: [String] = []
    var current = ""
    var state = QuoteState.unquoted
    var escaping = false

    for character in commandLine {
      if escaping {
        current.append(character)
        escaping = false
        continue
      }

      switch state {
      case .unquoted:
        switch character {
        case "\\":
          escaping = true
        case "\"":
          state = .double
        case "'":
          state = .single
        case _ where character.isWhitespace:
          if !current.isEmpty {
            tokens.append(current)
            current = ""
          }
        default:
          current.append(character)
        }
      case .single:
        if character == "'" {
          state = .unquoted
        } else {
          current.append(character)
        }
      case .double:
        switch character {
        case "\\":
          escaping = true
        case "\"":
          state = .unquoted
        default:
          current.append(character)
        }
      }
    }

    guard !escaping else {
      throw HatchError.message("editor command cannot end with an escape")
    }
    guard state == .unquoted else {
      throw HatchError.message("editor command contains an unterminated quote")
    }
    if !current.isEmpty {
      tokens.append(current)
    }
    guard let program = tokens.first, !program.isEmpty else {
      throw HatchError.message("invalid editor command")
    }
    return tokens
  }
}
