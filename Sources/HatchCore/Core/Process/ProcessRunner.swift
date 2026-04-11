import Foundation

public struct ProcessRunner {
  public init() {}

  @discardableResult
  public func run(
    _ program: String,
    arguments: [String],
    currentDirectory: URL? = nil,
    environment: [String: String]? = nil
  ) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [program] + arguments
    process.currentDirectoryURL = currentDirectory
    process.environment = environment ?? ProcessInfo.processInfo.environment

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let output =
      String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let errors =
      String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
      let message = errors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? output : errors
      throw HatchError.message(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func succeeds(
    _ program: String,
    arguments: [String],
    currentDirectory: URL? = nil
  ) -> Bool {
    do {
      _ = try run(program, arguments: arguments, currentDirectory: currentDirectory)
      return true
    } catch {
      return false
    }
  }
}
