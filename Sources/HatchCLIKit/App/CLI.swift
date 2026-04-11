import Foundation
import HatchCore

public struct HatchCLI {
  public init() {}

  public static func run(arguments: [String]) throws {
    guard let group = arguments.first else {
      printUsage()
      return
    }

    switch group {
    case "help", "--help", "-h":
      printUsage()
    case "project", "p":
      try runProject(arguments: Array(arguments.dropFirst()))
    case "task", "t":
      try runTask(arguments: Array(arguments.dropFirst()))
    case "checkout":
      try runCheckout(arguments: Array(arguments.dropFirst()))
    case "completions":
      try runCompletions(arguments: Array(arguments.dropFirst()))
    default:
      throw CLIError(message: "unknown command '\(group)'")
    }
  }
}
