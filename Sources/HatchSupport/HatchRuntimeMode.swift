import Foundation

public struct HatchRuntimeMode: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case normal
    case uiTest
    case demo
  }

  public let kind: Kind
  public let scenario: HatchUIScenario
  public let queryOverride: String?

  public init(kind: Kind, scenario: HatchUIScenario, queryOverride: String?) {
    self.kind = kind
    self.scenario = scenario
    self.queryOverride = queryOverride
  }

  public var isAutomation: Bool {
    kind != .normal
  }

  public var suppressesLoadErrors: Bool {
    isAutomation
  }

  public static func current(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = CommandLine.arguments
  ) -> Self {
    let kind: Kind =
      if boolFlag(
        environmentKeys: [HatchEnvironment.Key.uiTestMode],
        arguments: arguments,
        argumentFlags: ["--ui-test-mode"],
        environment: environment
      ) || environment[HatchEnvironment.Key.uiTestScenario] != nil
        || environment[HatchEnvironment.Key.uiTestQuery] != nil
        || environment[HatchEnvironment.Key.xcodeUITestConfiguration] != nil
      {
        .uiTest
      } else if boolFlag(
        environmentKeys: [HatchEnvironment.Key.demoMode],
        arguments: arguments,
        argumentFlags: ["--demo-mode"],
        environment: environment
      ) {
        .demo
      } else {
        .normal
      }

    let scenario = scenario(
      environmentKeys: [HatchEnvironment.Key.uiTestScenario, HatchEnvironment.Key.demoScenario],
      arguments: arguments,
      environment: environment
    )

    let queryOverride = stringValue(
      environmentKeys: [HatchEnvironment.Key.uiTestQuery, HatchEnvironment.Key.demoQuery],
      arguments: arguments,
      argumentFlags: ["--ui-test-query", "--demo-query"],
      environment: environment
    )

    return HatchRuntimeMode(kind: kind, scenario: scenario, queryOverride: queryOverride)
  }

  private static func boolFlag(
    environmentKeys: [String],
    arguments: [String],
    argumentFlags: [String],
    environment: [String: String]
  ) -> Bool {
    for key in environmentKeys {
      if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
        ["1", "true", "yes"].contains(value.lowercased())
      {
        return true
      }
    }

    return argumentFlags.contains { arguments.contains($0) }
  }

  private static func scenario(
    environmentKeys: [String],
    arguments: [String],
    environment: [String: String]
  ) -> HatchUIScenario {
    for key in environmentKeys {
      if let value = environment[key],
        let scenario = HatchUIScenario(
          rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
      {
        return scenario
      }
    }

    for (index, argument) in arguments.enumerated() {
      if argument == "--ui-test-scenario" || argument == "--demo-scenario" {
        guard index + 1 < arguments.count else { continue }
        if let scenario = HatchUIScenario(rawValue: arguments[index + 1].lowercased()) {
          return scenario
        }
      }

      if let rawValue = argument.split(separator: "=", maxSplits: 1).dropFirst().first,
        argument.hasPrefix("--ui-test-scenario=") || argument.hasPrefix("--demo-scenario="),
        let scenario = HatchUIScenario(rawValue: String(rawValue).lowercased())
      {
        return scenario
      }
    }

    return .none
  }

  private static func stringValue(
    environmentKeys: [String],
    arguments: [String],
    argumentFlags: [String],
    environment: [String: String]
  ) -> String? {
    for key in environmentKeys {
      if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
      {
        return value
      }
    }

    for (index, argument) in arguments.enumerated() {
      if argumentFlags.contains(argument) {
        guard index + 1 < arguments.count else { continue }
        let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
          return value
        }
      }

      if let rawValue = argument.split(separator: "=", maxSplits: 1).dropFirst().first,
        argumentFlags.contains(where: { argument.hasPrefix("\($0)=") })
      {
        let value = String(rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
          return value
        }
      }
    }

    return nil
  }
}
