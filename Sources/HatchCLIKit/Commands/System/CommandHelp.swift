extension HatchCLI {
  static func printUsage() {
    print(usageText())
  }
}

package func usageText() -> String {
  """
  usage: \(CLIConstants.executableName) <command>

  commands:
    p ...                         alias for project ...
    project create <project-name>
    project list
    project config <project-name>
    checkout [--force] <repo-or-url>
    t ...                         alias for task ...
    task create <project-name> <task-name>
    task resume <task-name>|<project-name/task-name>|<project-name> <task-name>
    task list [project-name]
    task clean [--yes]
    completions <zsh|bash|fish>
    completions init zsh
  """
}
