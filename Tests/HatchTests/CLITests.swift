import Foundation
import HatchCLIKit
import HatchCore

let cliTests: [TestCase] = [
  .init(name: "usage text includes commands", run: testUsageTextIncludesCommands),
  .init(name: "short aliases dispatch to project and task", run: testShortAliasesDispatchToProjectAndTaskCommands),
  .init(name: "unknown top-level command throws", run: testUnknownTopLevelCommandThrows),
  .init(name: "unknown task subcommand throws", run: testUnknownTaskSubcommandThrows),
  .init(name: "zsh completion script contains commands", run: testZshCompletionScriptContainsCommands),
  .init(name: "bash and fish completion scripts contain commands", run: testBashAndFishCompletionScriptsContainCommands),
  .init(name: "zshrc setup is idempotent", run: testEnsureZshrcSetupAddsManagedBlockOnce),
  .init(name: "zshrc setup preserves existing content and newline", run: testEnsureZshrcSetupPreservesExistingContent),
  .init(name: "zshrc setup preserves existing compinit", run: testEnsureZshrcSetupPreservesExistingCompinit),
  .init(name: "completions init rejects bash and fish", run: testCompletionsInitRejectsBashAndFish),
  .init(name: "checkout argument parsing handles force and url", run: testParseCheckoutArguments),
  .init(name: "checkout argument parsing rejects invalid arity", run: testParseCheckoutArgumentsRejectsInvalidArity),
  .init(name: "fuzzy matches prefer closer matches", run: testFuzzyTaskMatchesPreferCloserMatches),
  .init(name: "subsequence score works", run: testSubsequenceScoreRewardsOrderedMatches),
  .init(name: "task resume exact project task wins", run: testResolveTaskLookupExactProjectTask),
  .init(name: "task resume exact bare task beats fuzzy", run: testResolveTaskLookupExactBareTaskBeatsFuzzy),
  .init(name: "task resume ambiguous exact bare task errors", run: testResolveTaskLookupAmbiguousExactBareTask),
  .init(name: "task resume fuzzy clear winner auto selects", run: testResolveTaskLookupFuzzyClearWinner),
  .init(name: "task resume fuzzy close tie errors with closest matches", run: testResolveTaskLookupFuzzyTieErrors),
  .init(name: "task resume two arg missing task errors", run: testResolveTaskLookupMissingTwoArgTask),
  .init(name: "task repo directories only include repos", run: testTaskRepoDirectoriesOnlyIncludeGitRepos),
  .init(name: "cleanup candidates ignore non closed merged repos", run: testCleanupCandidatesIgnoreNonClosedMergedRepos),
  .init(name: "cleanup candidates sort consistently", run: testCleanupCandidatesSortConsistently),
  .init(name: "cleanup --yes selects all", run: testChooseCleanupCandidatesReturnsAllWithYes),
  .init(name: "cleanup rejects non-interactive without yes", run: testChooseCleanupCandidatesRejectsNonInteractiveWithoutYes),
  .init(name: "cleanup parses interactive selection", run: testChooseCleanupCandidatesParsesInteractiveSelection),
  .init(name: "cleanup invalid interactive selection fails", run: testChooseCleanupCandidatesRejectsInvalidSelection),
  .init(name: "current task context resolves enclosing task", run: testResolveCurrentTaskContextFindsEnclosingTask),
  .init(name: "current task context resolves symlinked path", run: testResolveCurrentTaskContextResolvesSymlink),
  .init(name: "current task context fails at project root", run: testResolveCurrentTaskContextFailsAtProjectRoot),
  .init(name: "current task context fails outside task", run: testResolveCurrentTaskContextFailsOutsideTask),
]

func testUsageTextIncludesCommands() throws {
  let text = usageText()
  try expect(text.contains("p ..."), "usage text missing project alias")
  try expect(text.contains("project create"), "usage text missing project create")
  try expect(text.contains("project config <project-name>"), "usage text missing project config")
  try expect(text.contains("checkout [--force]"), "usage text missing checkout")
  try expect(text.contains("t ..."), "usage text missing task alias")
  try expect(text.contains("task clean [--yes]"), "usage text missing task clean")
  try expect(text.contains("completions init zsh"), "usage text missing completions init")
}

func testShortAliasesDispatchToProjectAndTaskCommands() throws {
  try expectThrows(CLIError.self) {
    try HatchCLI.run(arguments: ["p"])
  }
  try expectThrows(CLIError.self) {
    try HatchCLI.run(arguments: ["t"])
  }
}

func testUnknownTopLevelCommandThrows() throws {
  try expectThrows(CLIError.self) {
    try HatchCLI.run(arguments: ["bogus"])
  }
}

func testUnknownTaskSubcommandThrows() throws {
  try expectThrows(CLIError.self) {
    try HatchCLI.run(arguments: ["task", "bogus"])
  }
}

func testZshCompletionScriptContainsCommands() throws {
  let script = renderCompletionScript(shell: .zsh)
  try expect(script.contains("'p:Alias for project'"), "missing project alias completion")
  try expect(script.contains("project"), "missing project completion")
  try expect(script.contains("'t:Alias for task'"), "missing task alias completion")
  try expect(script.contains("task"), "missing task completion")
  try expect(script.contains("checkout"), "missing checkout completion")
  try expect(script.contains("completions"), "missing completions completion")
}

func testBashAndFishCompletionScriptsContainCommands() throws {
  let bash = renderCompletionScript(shell: .bash)
  let fish = renderCompletionScript(shell: .fish)
  try expect(bash.contains("p project t task checkout completions"), "bash completions missing commands")
  try expect(bash.contains("create list config"), "bash completions missing project config")
  try expect(fish.contains("complete -c hatch -f -n '__fish_use_subcommand' -a 'p'"), "fish completions missing project alias")
  try expect(fish.contains("create list config"), "fish completions missing project config")
  try expect(fish.contains("complete -c hatch"), "fish completions missing command declarations")
}

func testEnsureZshrcSetupAddsManagedBlockOnce() throws {
  try withTempDirectory { temp in
    let zshrc = temp.appendingPathComponent(".zshrc")
    let first = try ensureZshrcSetup(path: zshrc)
    let second = try ensureZshrcSetup(path: zshrc)
    let contents = try String(contentsOf: zshrc, encoding: .utf8)
    try expect(first == .addedManagedBlock, "expected first zshrc update to add block")
    try expect(second == .alreadyConfigured, "expected second zshrc update to be idempotent")
    try expect(contents.contains("hatch completions zsh"), "expected zshrc block contents")
  }
}

func testEnsureZshrcSetupPreservesExistingContent() throws {
  try withTempDirectory { temp in
    let zshrc = temp.appendingPathComponent(".zshrc")
    try "export PATH=$PATH\n".write(to: zshrc, atomically: true, encoding: .utf8)
    _ = try ensureZshrcSetup(path: zshrc)
    let contents = try String(contentsOf: zshrc, encoding: .utf8)
    try expect(contents.hasPrefix("export PATH=$PATH\n\n"), "expected existing zshrc content to be preserved")
  }
}

func testEnsureZshrcSetupPreservesExistingCompinit() throws {
  try withTempDirectory { temp in
    let zshrc = temp.appendingPathComponent(".zshrc")
    try "autoload -Uz compinit\ncompinit\n".write(to: zshrc, atomically: true, encoding: .utf8)
    _ = try ensureZshrcSetup(path: zshrc)
    let contents = try String(contentsOf: zshrc, encoding: .utf8)
    try expect(contents.components(separatedBy: "compinit").count - 1 == 2, "expected existing compinit to remain without duplicate managed compinit")
    try expect(contents.contains("eval \"$(hatch completions zsh)\""), "expected managed completion block")
  }
}

func testCompletionsInitRejectsBashAndFish() throws {
  try expectThrows(HatchError.self) {
    try HatchCLI.run(arguments: ["completions", "init", "bash"])
  }
  try expectThrows(HatchError.self) {
    try HatchCLI.run(arguments: ["completions", "init", "fish"])
  }
}

func testParseCheckoutArguments() throws {
  let parsed = try parseCheckoutArguments(["--force", "https://github.com/acme/api.git"])
  try expect(parsed.force, "expected force to be true")
  try expect(parsed.repoInput == "https://github.com/acme/api.git", "unexpected repo input")
}

func testParseCheckoutArgumentsRejectsInvalidArity() throws {
  try expectThrows(CLIError.self) {
    _ = try parseCheckoutArguments([])
  }
  try expectThrows(CLIError.self) {
    _ = try parseCheckoutArguments(["one", "two"])
  }
}

func testFuzzyTaskMatchesPreferCloserMatches() throws {
  let tasks = [
    TaskSummary(project: "alpha", task: "api", path: URL(fileURLWithPath: "/tmp/alpha/api")),
    TaskSummary(project: "beta", task: "api-server", path: URL(fileURLWithPath: "/tmp/beta/api-server")),
  ]
  let matches = fuzzyTaskMatches(for: "api", tasks: tasks)
  try expect(matches.map(\.label) == ["alpha/api", "beta/api-server"], "unexpected fuzzy match order")
}

func testSubsequenceScoreRewardsOrderedMatches() throws {
  try expect(fuzzyScore(query: "apr", candidate: "api-router") > 0, "expected subsequence score")
  try expect(fuzzyScore(query: "zzz", candidate: "api-router") == 0, "expected zero for non-match")
}

func testResolveTaskLookupExactProjectTask() throws {
  let tasks = sampleTasksForLookup()
  let task = try resolveTaskLookup(arguments: ["alpha/api"], tasks: tasks)
  try expect(task.project == "alpha" && task.task == "api", "expected exact project/task match")
}

func testResolveTaskLookupExactBareTaskBeatsFuzzy() throws {
  let tasks = sampleTasksForLookup()
  let task = try resolveTaskLookup(arguments: ["api"], tasks: tasks)
  try expect(task.project == "alpha" && task.task == "api", "expected exact bare task match")
}

func testResolveTaskLookupAmbiguousExactBareTask() throws {
  let tasks = [
    TaskSummary(project: "alpha", task: "api", path: URL(fileURLWithPath: "/tmp/alpha/api")),
    TaskSummary(project: "beta", task: "api", path: URL(fileURLWithPath: "/tmp/beta/api")),
  ]
  try expectThrows(HatchError.self) {
    _ = try resolveTaskLookup(arguments: ["api"], tasks: tasks)
  }
}

func testResolveTaskLookupFuzzyClearWinner() throws {
  let tasks = [
    TaskSummary(project: "alpha", task: "authentication-refresh", path: URL(fileURLWithPath: "/tmp/a")),
    TaskSummary(project: "beta", task: "docs", path: URL(fileURLWithPath: "/tmp/b")),
  ]
  let task = try resolveTaskLookup(arguments: ["authrefresh"], tasks: tasks)
  try expect(task.project == "alpha", "expected fuzzy clear winner")
}

func testResolveTaskLookupFuzzyTieErrors() throws {
  let tasks = [
    TaskSummary(project: "alpha", task: "api-server", path: URL(fileURLWithPath: "/tmp/a")),
    TaskSummary(project: "beta", task: "api-service", path: URL(fileURLWithPath: "/tmp/b")),
  ]
  try expectThrows(HatchError.self) {
    _ = try resolveTaskLookup(arguments: ["apis"], tasks: tasks)
  }
}

func testResolveTaskLookupMissingTwoArgTask() throws {
  try expectThrows(HatchError.self) {
    _ = try resolveTaskLookup(arguments: ["alpha", "missing"], tasks: sampleTasksForLookup())
  }
}

func testTaskRepoDirectoriesOnlyIncludeGitRepos() throws {
  try withTempDirectory { root in
    let taskPath = root.appendingPathComponent("alpha/task-a", isDirectory: true)
    let repoPath = taskPath.appendingPathComponent("api", isDirectory: true)
    let nonRepoPath = taskPath.appendingPathComponent("notes", isDirectory: true)
    try FileManager.default.createDirectory(at: repoPath.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: nonRepoPath, withIntermediateDirectories: true)

    let task = TaskSummary(project: "alpha", task: "task-a", path: taskPath)
    let repos = taskRepoDirectories(for: task)
    try expect(repos.count == 1, "expected exactly one git repo directory")
    try expect(repos.first?.lastPathComponent == repoPath.lastPathComponent, "expected api repo directory")
  }
}

func testCleanupCandidatesIgnoreNonClosedMergedRepos() throws {
  let tasks = [
    TaskSummary(project: "alpha", task: "task-a", path: URL(fileURLWithPath: "/tmp/task-a")),
    TaskSummary(project: "beta", task: "task-b", path: URL(fileURLWithPath: "/tmp/task-b")),
  ]
  let candidates = [
    CleanupCandidate(task: tasks[0], label: "alpha/task-a", repoStates: ["api:OPEN"]),
    CleanupCandidate(task: tasks[1], label: "beta/task-b", repoStates: ["web:CLOSED"]),
  ]
  let filtered = candidates.filter { $0.repoStates.contains { $0.hasSuffix(":CLOSED") || $0.hasSuffix(":MERGED") } }
  try expect(filtered.map(\.label) == ["beta/task-b"], "expected only closed or merged candidates")
}

func testCleanupCandidatesSortConsistently() throws {
  let candidates = [
    CleanupCandidate(task: TaskSummary(project: "beta", task: "b", path: URL(fileURLWithPath: "/tmp/b")), label: "beta/b", repoStates: ["x:MERGED"]),
    CleanupCandidate(task: TaskSummary(project: "alpha", task: "a", path: URL(fileURLWithPath: "/tmp/a")), label: "alpha/a", repoStates: ["y:CLOSED"]),
  ].sorted { $0.label < $1.label }
  try expect(candidates.map(\.label) == ["alpha/a", "beta/b"], "expected deterministic cleanup candidate sorting")
}

func testChooseCleanupCandidatesReturnsAllWithYes() throws {
  let selected = try chooseCleanupCandidates(sampleCleanupCandidates(), deleteAll: true, isInteractive: false) {
    nil
  }
  try expect(selected == [0, 1], "expected all cleanup candidates to be selected")
}

func testChooseCleanupCandidatesRejectsNonInteractiveWithoutYes() throws {
  try expectThrows(HatchError.self) {
    _ = try chooseCleanupCandidates(sampleCleanupCandidates(), deleteAll: false, isInteractive: false) {
      nil
    }
  }
}

func testChooseCleanupCandidatesParsesInteractiveSelection() throws {
  let selected = try chooseCleanupCandidates(sampleCleanupCandidates(), deleteAll: false, isInteractive: true) {
    "2, 1"
  }
  try expect(selected == [0, 1], "expected normalized cleanup selections")
}

func testChooseCleanupCandidatesRejectsInvalidSelection() throws {
  try expectThrows(HatchError.self) {
    _ = try chooseCleanupCandidates(sampleCleanupCandidates(), deleteAll: false, isInteractive: true) { "3" }
  }
}

func testResolveCurrentTaskContextFindsEnclosingTask() throws {
  try withTempDirectory { root in
    let taskPath = root.appendingPathComponent("alpha/task-a", isDirectory: true)
    let nested = taskPath.appendingPathComponent("subdir/deeper", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("alpha/.project"), atomically: true, encoding: .utf8)

    let context = try resolveCurrentTaskContext(from: nested)
    try expect(context.project.name == "alpha", "wrong project name")
    try expect(context.task.task == "task-a", "wrong task name")
    try expect(context.task.path == taskPath, "wrong task path")
  }
}

func testResolveCurrentTaskContextResolvesSymlink() throws {
  try withTempDirectory { root in
    let taskPath = root.appendingPathComponent("alpha/task-a", isDirectory: true)
    try FileManager.default.createDirectory(at: taskPath, withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("alpha/.project"), atomically: true, encoding: .utf8)
    let symlink = root.appendingPathComponent("task-link")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: taskPath)

    let context = try resolveCurrentTaskContext(from: symlink)
    try expect(context.task.path == taskPath, "expected canonical task path from symlink")
  }
}

func testResolveCurrentTaskContextFailsAtProjectRoot() throws {
  try withTempDirectory { root in
    let project = root.appendingPathComponent("alpha", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try "".write(to: project.appendingPathComponent(".project"), atomically: true, encoding: .utf8)
    try expectThrows(HatchError.self) {
      _ = try resolveCurrentTaskContext(from: project)
    }
  }
}

func testResolveCurrentTaskContextFailsOutsideTask() throws {
  try withTempDirectory { root in
    try expectThrows(HatchError.self) {
      _ = try resolveCurrentTaskContext(from: root)
    }
  }
}

func sampleCleanupCandidates() -> [CleanupCandidate] {
  [
    CleanupCandidate(
      task: TaskSummary(project: "alpha", task: "one", path: URL(fileURLWithPath: "/tmp/one")),
      label: "alpha/one",
      repoStates: ["api:MERGED"]
    ),
    CleanupCandidate(
      task: TaskSummary(project: "beta", task: "two", path: URL(fileURLWithPath: "/tmp/two")),
      label: "beta/two",
      repoStates: ["web:CLOSED"]
    ),
  ]
}

func sampleTasksForLookup() -> [TaskSummary] {
  [
    TaskSummary(project: "alpha", task: "api", path: URL(fileURLWithPath: "/tmp/alpha/api")),
    TaskSummary(project: "beta", task: "api-service", path: URL(fileURLWithPath: "/tmp/beta/api-service")),
    TaskSummary(project: "gamma", task: "docs", path: URL(fileURLWithPath: "/tmp/gamma/docs")),
  ]
}
