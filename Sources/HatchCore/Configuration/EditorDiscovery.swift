import AppKit
import Foundation

public struct EditorDiscoveryResult: Equatable, Sendable {
  public let recommended: String?
  public let examples: [String]

  public init(recommended: String?, examples: [String]) {
    self.recommended = recommended
    self.examples = examples
  }
}

public enum EditorDiscovery {
  public static func current(
    runner: ProcessRunner = ProcessRunner(),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> EditorDiscoveryResult {
    discover(
      environment: environment,
      commandExists: { command in
        runner.succeeds("which", arguments: [command])
      },
      hasApplication: { bundleIdentifier in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
      }
    )
  }

  public static func discover(
    environment: [String: String],
    commandExists: (String) -> Bool,
    hasApplication: (String) -> Bool
  ) -> EditorDiscoveryResult {
    var examples: [String] = []

    func append(_ candidate: String?) {
      guard let candidate else { return }
      let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !examples.contains(trimmed) else { return }
      examples.append(trimmed)
    }

    append(environment["VISUAL"])
    append(environment["EDITOR"])

    for command in ["zed", "cursor", "code", "subl", "mate", "bbedit"] {
      if commandExists(command) {
        append(command)
      }
    }

    let applications = [
      ("dev.zed.Zed", #"open -a "Zed""#),
      ("com.todesktop.230313mzl4w4u92", #"open -a "Cursor""#),
      ("com.microsoft.VSCode", #"open -a "Visual Studio Code""#),
      ("com.sublimetext.4", #"open -a "Sublime Text""#),
      ("com.macromates.TextMate", #"open -a "TextMate""#),
      ("com.barebones.bbedit", #"open -a "BBEdit""#),
    ]

    for (bundleIdentifier, command) in applications where hasApplication(bundleIdentifier) {
      append(command)
    }

    return EditorDiscoveryResult(
      recommended: examples.first,
      examples: examples
    )
  }
}
