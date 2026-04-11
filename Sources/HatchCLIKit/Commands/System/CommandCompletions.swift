import Foundation
import HatchCore

public enum CompletionShell: String {
  case bash
  case fish
  case zsh
}

public enum ZshRcUpdate: Equatable {
  case addedManagedBlock
  case alreadyConfigured
}

private let hatchZshRcBlockStart = "# >>> hatch completions >>>"
private let hatchZshRcBlockEnd = "# <<< hatch completions <<<"

extension HatchCLI {
  static func runCompletions(arguments: [String]) throws {
    guard let first = arguments.first else {
      throw CLIError(
        message: "usage: \(CLIConstants.executableName) completions <zsh|bash|fish>|init zsh")
    }

    if first == "init" {
      try initCompletions(arguments: Array(arguments.dropFirst()))
      return
    }

    guard arguments.count == 1, let shell = CompletionShell(rawValue: first) else {
      throw CLIError(message: "usage: \(CLIConstants.executableName) completions <zsh|bash|fish>")
    }
    print(renderCompletionScript(shell: shell))
  }

  private static func initCompletions(arguments: [String]) throws {
    guard arguments.count == 1, let shell = CompletionShell(rawValue: arguments[0]) else {
      throw CLIError(message: "usage: \(CLIConstants.executableName) completions init zsh")
    }
    guard shell == .zsh else {
      throw HatchError.message(
        "automatic shell bootstrap currently supports zsh only; use `hatch completions \(shell.rawValue)` to print the script"
      )
    }

    let homeDirectory =
      ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 }
      ?? NSHomeDirectory()
    let zshrc = URL(fileURLWithPath: homeDirectory).appendingPathComponent(".zshrc")
    switch try ensureZshrcSetup(path: zshrc) {
    case .addedManagedBlock:
      print("Updated \(zshrc.path) to load hatch completions on shell startup.")
    case .alreadyConfigured:
      print("\(zshrc.path) is already configured for hatch completions.")
    }
    print("Reload your shell or run `exec zsh` to pick up the new completions.")
  }
}

package func renderCompletionScript(shell: CompletionShell) -> String {
  switch shell {
  case .zsh:
    return zshCompletionScript()
  case .bash:
    return bashCompletionScript()
  case .fish:
    return fishCompletionScript()
  }
}

package func ensureZshrcSetup(path: URL, fileManager: FileManager = .default) throws -> ZshRcUpdate
{
  let existing: String
  do {
    existing = try String(contentsOf: path, encoding: .utf8)
  } catch let error as NSError
    where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
  {
    existing = ""
  }

  if existing.contains(hatchZshRcBlockStart) {
    return .alreadyConfigured
  }

  var updated = existing
  if !updated.isEmpty && !updated.hasSuffix("\n") {
    updated.append("\n")
  }
  if !updated.isEmpty {
    updated.append("\n")
  }
  updated.append(zshrcBlock(hasCompinit: updated.contains("compinit")))

  try updated.write(to: path, atomically: true, encoding: .utf8)
  return .addedManagedBlock
}

package func zshrcBlock(hasCompinit: Bool) -> String {
  var block = ""
  block.append("\(hatchZshRcBlockStart)\n")
  if !hasCompinit {
    block.append("autoload -Uz compinit\n")
    block.append("compinit\n")
  }
  block.append("eval \"$(hatch completions zsh)\"\n")
  block.append("\(hatchZshRcBlockEnd)\n")
  return block
}

private func zshCompletionScript() -> String {
  """
  #compdef hatch

  _hatch() {
    local -a commands
    commands=(
      'p:Alias for project'
      'project:Create and manage projects'
      't:Alias for task'
      'task:Create, resume, list, and clean tasks'
      'checkout:Check out a repository into the current task'
      'completions:Generate or install shell completions'
    )

    if (( CURRENT == 2 )); then
      _describe 'command' commands
      return
    fi

    case "$words[2]" in
      p|project)
        _arguments '1: :((create list config))'
        ;;
      t|task)
        _arguments '1: :((create resume list clean))'
        ;;
      checkout)
        _arguments '--force[Replace an existing repo checkout]' '1:repo or url:_files'
        ;;
      completions)
        _arguments '1: :((bash fish zsh init))' '2: :((zsh))'
        ;;
    esac
  }

  _hatch "$@"
  """
}

private func bashCompletionScript() -> String {
  """
  _hatch_completions() {
    local cur prev words cword
    _init_completion || return

    if [[ $cword -eq 1 ]]; then
      COMPREPLY=( $(compgen -W "p project t task checkout completions" -- "$cur") )
      return
    fi

    case "${words[1]}" in
      p|project)
        COMPREPLY=( $(compgen -W "create list config" -- "$cur") )
        ;;
      t|task)
        COMPREPLY=( $(compgen -W "create resume list clean" -- "$cur") )
        ;;
      completions)
        COMPREPLY=( $(compgen -W "bash fish zsh init" -- "$cur") )
        ;;
    esac
  }

  complete -F _hatch_completions hatch
  """
}

private func fishCompletionScript() -> String {
  """
  complete -c hatch -f -n '__fish_use_subcommand' -a 'p' -d 'Alias for project'
  complete -c hatch -f -n '__fish_use_subcommand' -a 'project' -d 'Create and manage projects'
  complete -c hatch -f -n '__fish_use_subcommand' -a 't' -d 'Alias for task'
  complete -c hatch -f -n '__fish_use_subcommand' -a 'task' -d 'Create, resume, list, and clean tasks'
  complete -c hatch -f -n '__fish_use_subcommand' -a 'checkout' -d 'Check out a repository into the current task'
  complete -c hatch -f -n '__fish_use_subcommand' -a 'completions' -d 'Generate or install shell completions'

  complete -c hatch -f -n '__fish_seen_subcommand_from p project' -a 'create list config'
  complete -c hatch -f -n '__fish_seen_subcommand_from t task' -a 'create resume list clean'
  complete -c hatch -f -n '__fish_seen_subcommand_from completions' -a 'bash fish zsh init'
  """
}
