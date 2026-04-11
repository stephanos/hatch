import Foundation
import HatchCore
import HatchSupport

struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

final class ErrorBox: @unchecked Sendable {
  var error: Error?
}

struct TestCase: Sendable {
  let name: String
  let run: @Sendable () throws -> Void
}

func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) throws {
  if !condition() {
    throw TestFailure(description: message())
  }
}

func expectThrows<T>(
  _ expectedType: T.Type = T.self,
  _ body: () throws -> Void
) throws where T: Error {
  do {
    try body()
    throw TestFailure(description: "Expected \(expectedType) to be thrown")
  } catch is T {
    return
  } catch {
    throw TestFailure(description: "Expected \(expectedType), got \(type(of: error))")
  }
}

func withTempDirectory(_ body: (URL) throws -> Void) throws {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try body(directory)
}

func onMainActor(_ body: @escaping @MainActor () throws -> Void) throws {
  if Thread.isMainThread {
    try MainActor.assumeIsolated {
      try body()
    }
    return
  }

  let semaphore = DispatchSemaphore(value: 0)
  let errorBox = ErrorBox()
  Task { @MainActor in
    do {
      try body()
    } catch {
      errorBox.error = error
    }
    semaphore.signal()
  }
  semaphore.wait()
  if let thrown = errorBox.error {
    throw thrown
  }
}

func withEnvironment(
  _ updates: [String: String],
  unset keysToUnset: [String] = [],
  _ body: () throws -> Void
) throws {
  var previous: [String: String?] = [:]
  for (key, value) in updates {
    previous[key] = ProcessInfo.processInfo.environment[key]
    setenv(key, value, 1)
  }
  for key in keysToUnset {
    if previous[key] == nil {
      previous[key] = ProcessInfo.processInfo.environment[key]
    }
    unsetenv(key)
  }

  defer {
    for (key, value) in previous {
      if let value {
        setenv(key, value, 1)
      } else {
        unsetenv(key)
      }
    }
  }

  try body()
}

struct IntegrationEnvironment {
  let root: URL
  let configDir: URL
  let workspaceRoot: URL
  let binDir: URL
  let editorLog: URL
  let repoRoot: URL
  let workspaceConfig: WorkspaceConfig

  var bootstrap: BootstrapConfig {
    BootstrapConfig(workspaceRoot: workspaceRoot.path, cliInstallPath: binDir.path)
  }
}

struct TestWorkspaceFixture {
  let environment: IntegrationEnvironment
  let inheritedPath: String

  var cliEnvironment: [String: String] {
    [
      HatchEnvironment.Key.configDir: environment.configDir.path,
      "PATH": "\(environment.binDir.path):\(inheritedPath)",
    ]
  }

  func runCLI(
    arguments: [String],
    currentDirectory: URL? = nil,
    standardInput: String? = nil,
    extraEnvironment: [String: String] = [:]
  ) throws -> CLIRunResult {
    try executeCLI(
      repoRoot: environment.repoRoot,
      arguments: arguments,
      environment: cliEnvironment.merging(extraEnvironment, uniquingKeysWith: { _, new in new }),
      currentDirectory: currentDirectory,
      standardInput: standardInput
    )
  }

  func runCLIViaTTY(
    arguments: [String],
    currentDirectory: URL? = nil,
    standardInput: String = "",
    extraEnvironment: [String: String] = [:]
  ) throws -> CLIRunResult {
    try executeCLIViaTTY(
      repoRoot: environment.repoRoot,
      arguments: arguments,
      environment: cliEnvironment.merging(extraEnvironment, uniquingKeysWith: { _, new in new }),
      currentDirectory: currentDirectory,
      standardInput: standardInput
    )
  }
}

struct IntegrationEnvironmentBuilder {
  var rootName = UUID().uuidString
  var defaultOrg = "acme"
  var defaultRepos = ["api"]
  var branchTemplate = "{user}/{task}"
  var editor = "zed"
  var hooksInclude: [String] = []
  var hooks: [HookName: HookDefinition] = [:]

  func build(from sandboxRoot: URL) -> IntegrationEnvironment {
    IntegrationEnvironment(
      root: sandboxRoot,
      configDir: sandboxRoot.appendingPathComponent("config", isDirectory: true),
      workspaceRoot: sandboxRoot.appendingPathComponent("Workspace", isDirectory: true),
      binDir: sandboxRoot.appendingPathComponent("bin", isDirectory: true),
      editorLog: sandboxRoot.appendingPathComponent("editor.log"),
      repoRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
      workspaceConfig: workspaceConfig()
    )
  }

  func workspaceConfig() -> WorkspaceConfig {
    WorkspaceConfig(
      defaultOrg: defaultOrg,
      defaultRepos: defaultRepos,
      branchTemplate: branchTemplate,
      editor: editor,
      hooksInclude: hooksInclude,
      hooks: hooks
    )
  }
}

func withIntegrationEnvironment(_ body: (IntegrationEnvironment) throws -> Void) throws {
  try withIntegrationEnvironment(configure: { _ in }, body)
}

func withNamedIntegrationEnvironment(
  rootName: String,
  _ body: (IntegrationEnvironment) throws -> Void
) throws {
  try withIntegrationEnvironment(
    configure: { builder in
      builder.rootName = rootName
    },
    body
  )
}

func withIntegrationEnvironment(
  configure: (inout IntegrationEnvironmentBuilder) -> Void,
  _ body: (IntegrationEnvironment) throws -> Void
) throws {
  var builder = IntegrationEnvironmentBuilder()
  configure(&builder)

  try withTempDirectory { root in
    let sandboxRoot = root.appendingPathComponent(builder.rootName, isDirectory: true)
    let environment = builder.build(from: sandboxRoot)
    let configDir = environment.configDir
    let workspaceRoot = environment.workspaceRoot
    let binDir = environment.binDir
    let editorLog = environment.editorLog

    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

    try writeExecutable(
      at: binDir.appendingPathComponent("git"),
      body: gitStubScript()
    )
    try writeExecutable(
      at: binDir.appendingPathComponent("gh"),
      body: ghStubScript()
    )
    try writeExecutable(
      at: binDir.appendingPathComponent("zed"),
      body: """
      #!/bin/sh
      if [ "${EDITOR_FAIL:-}" = "1" ]; then
        printf 'editor failed\\n' >&2
        exit 1
      fi
      printf '%s\\n' "$@" >> "\(editorLog.path)"
      """
    )

    let path = "\(binDir.path):" + (ProcessInfo.processInfo.environment["PATH"] ?? "")
    try withEnvironment([HatchEnvironment.Key.configDir: configDir.path, "PATH": path]) {
      try body(environment)
    }
  }
}

func withIntegrationFixture(
  configure: (inout IntegrationEnvironmentBuilder) -> Void = { _ in },
  _ body: (TestWorkspaceFixture) throws -> Void
) throws {
  try withIntegrationEnvironment(configure: configure) { environment in
    let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    try body(TestWorkspaceFixture(environment: environment, inheritedPath: inheritedPath))
  }
}

struct CLIRunResult {
  let status: Int32
  let stdout: String
  let stderr: String
}

func runCLI(
  repoRoot: URL,
  arguments: [String],
  environment: [String: String],
  currentDirectory: URL? = nil,
  standardInput: String? = nil
) throws -> CLIRunResult {
  try executeCLI(
    repoRoot: repoRoot,
    arguments: arguments,
    environment: environment,
    currentDirectory: currentDirectory,
    standardInput: standardInput
  )
}

private func executeCLI(
  repoRoot: URL,
  arguments: [String],
  environment: [String: String],
  currentDirectory: URL? = nil,
  standardInput: String? = nil
) throws -> CLIRunResult {
  let process = Process()
  process.executableURL = try resolveCLIBinary(repoRoot: repoRoot)
  process.arguments = arguments
  process.currentDirectoryURL = currentDirectory ?? repoRoot
  process.environment = environment

  let stdout = Pipe()
  let stderr = Pipe()
  let stdin = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr
  process.standardInput = stdin

  try process.run()
  if let standardInput {
    stdin.fileHandleForWriting.write(Data(standardInput.utf8))
  }
  try? stdin.fileHandleForWriting.close()
  process.waitUntilExit()

  return CLIRunResult(
    status: process.terminationStatus,
    stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
    stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  )
}

func runCLIViaTTY(
  repoRoot: URL,
  arguments: [String],
  environment: [String: String],
  currentDirectory: URL? = nil,
  standardInput: String = ""
) throws -> CLIRunResult {
  try executeCLIViaTTY(
    repoRoot: repoRoot,
    arguments: arguments,
    environment: environment,
    currentDirectory: currentDirectory,
    standardInput: standardInput
  )
}

private func executeCLIViaTTY(
  repoRoot: URL,
  arguments: [String],
  environment: [String: String],
  currentDirectory: URL? = nil,
  standardInput: String = ""
) throws -> CLIRunResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
  let binaryPath = try resolveCLIBinary(repoRoot: repoRoot).path
  let command = shellQuote(binaryPath) + " " + arguments.map(shellQuote).joined(separator: " ")
  process.arguments = ["-q", "/dev/null", "/bin/sh", "-lc", command]
  process.currentDirectoryURL = currentDirectory ?? repoRoot
  process.environment = environment

  let stdout = Pipe()
  let stderr = Pipe()
  let stdin = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr
  process.standardInput = stdin

  try process.run()
  if !standardInput.isEmpty {
    stdin.fileHandleForWriting.write(Data(standardInput.utf8))
  }
  try? stdin.fileHandleForWriting.close()
  process.waitUntilExit()

  return CLIRunResult(
    status: process.terminationStatus,
    stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
    stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  )
}

func makeGitOnlyPath(from env: IntegrationEnvironment) throws -> String {
  let gitOnlyBin = env.root.appendingPathComponent("git-only-bin", isDirectory: true)
  try FileManager.default.createDirectory(at: gitOnlyBin, withIntermediateDirectories: true)
  let destination = gitOnlyBin.appendingPathComponent("git")
  if !FileManager.default.fileExists(atPath: destination.path) {
    try FileManager.default.copyItem(
      at: env.binDir.appendingPathComponent("git"),
      to: destination
    )
  }
  return "\(gitOnlyBin.path):/usr/bin:/bin:/usr/sbin:/sbin"
}

func writeExecutable(at url: URL, body: String) throws {
  try body.write(to: url, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

func lastNonEmptyLine(in text: String) -> String? {
  text
    .split(separator: "\n", omittingEmptySubsequences: true)
    .map(String.init)
    .last
}

private func shellQuote(_ value: String) -> String {
  "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func resolveCLIBinary(repoRoot: URL) throws -> URL {
  let cacheKey = repoRoot.standardizedFileURL.path
  if let cached = CLIBinaryCache.shared.value(for: cacheKey) {
    return cached
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
  process.arguments = ["build", "--package-path", repoRoot.path, "--product", "hatch-cli", "--show-bin-path"]
  process.currentDirectoryURL = repoRoot

  let stdout = Pipe()
  let stderr = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  process.waitUntilExit()

  let binPath = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  if process.terminationStatus != 0 || binPath.isEmpty {
    let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown swift build failure"
    throw TestFailure(description: "Failed to resolve hatch-cli binary: \(errorOutput)")
  }

  let binaryURL = URL(fileURLWithPath: binPath).appendingPathComponent("hatch-cli")
  CLIBinaryCache.shared.insert(binaryURL, for: cacheKey)
  return binaryURL
}

private final class CLIBinaryCache: @unchecked Sendable {
  static let shared = CLIBinaryCache()

  private let lock = NSLock()
  private var storage: [String: URL] = [:]

  func value(for key: String) -> URL? {
    lock.lock()
    defer { lock.unlock() }
    return storage[key]
  }

  func insert(_ value: URL, for key: String) {
    lock.lock()
    storage[key] = value
    lock.unlock()
  }
}

private func gitStubScript() -> String {
  """
  #!/bin/sh
  if [ "$1" = "clone" ]; then
    if [ "${GIT_FAIL_CLONE:-}" = "1" ]; then
      printf 'clone failed\\n' >&2
      exit 1
    fi
    clone_url="$2"
    dest="$3"
    mkdir -p "$dest/.git"
    printf '%s\\n' "$clone_url" > "$dest/.clone_url"
    printf '%s\\n' "main" > "$dest/.branch"
    exit 0
  fi

  if [ "$1" = "-C" ]; then
    repo="$2"
    shift 2
    if [ "$1" = "show-ref" ]; then
      ref="$5"
      if [ -n "${GIT_MISSING_BRANCHES:-}" ]; then
        case ",$GIT_MISSING_BRANCHES," in
          *",$ref,"*)
            exit 1
            ;;
        esac
      fi
      case "$ref" in
        refs/remotes/origin/main|refs/remotes/origin/develop|refs/remotes/origin/master)
          exit 0
          ;;
        *)
          exit 1
          ;;
      esac
    fi
    if [ "$1" = "checkout" ] && [ "$2" = "-b" ]; then
      printf '%s\\n' "$3" > "$repo/.branch"
      exit 0
    fi
    if [ "$1" = "rev-parse" ]; then
      if [ -f "$repo/.branch" ]; then
        cat "$repo/.branch"
      else
        printf 'main\\n'
      fi
      exit 0
    fi
  fi

  printf 'unsupported git invocation\\n' >&2
  exit 1
  """
}

private func ghStubScript() -> String {
  """
  #!/bin/sh
  if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    case "$3" in
      merged-branch)
        printf 'MERGED\\n'
        ;;
      closed-branch)
        printf 'CLOSED\\n'
        ;;
      *)
        printf 'OPEN\\n'
        ;;
    esac
    exit 0
  fi
  printf 'unsupported gh invocation\\n' >&2
  exit 1
  """
}
