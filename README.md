# hatch

[![release](https://img.shields.io/github/v/release/stephanos/hatch)](https://github.com/stephanos/hatch/releases/latest)

`hatch` is a CLI for task-scoped Git workspaces, built for AI-assisted development.

It creates disposable workspaces with isolated repo checkouts and agent context.

## Quick Start

**1. Install**

```sh
curl -fsSL https://raw.githubusercontent.com/stephanos/hatch/main/install.sh | sh
```

Or download the [latest release](https://github.com/stephanos/hatch/releases/latest) manually and copy the `hatch` binary to your `$PATH`.

**2. Init**

Choose where projects should live.

```sh
hatch workspace new ~/Workspace
```

**3. Create projects and tasks**

Tasks belong to projects.

```sh
hatch project new my-project
hatch task new my-project my-task
```

This creates `<workspace>/my-project/my-task`.

**4. Open a task**

To open a task (directory) in your default editor:

```sh
hatch task open my-task
# or
hatch task open https://github.com/acme/web/pull/123
```

This fuzzy matches tasks across all projects, or resolves GitHub PR URLs.

_Tip: Add [tab completion](#tab-completion) to your shell and customize which [editor](#editor) to open._

**5. Clone a repo**

Clone a repo into the task as a new local branch `<github username>/<task name>`.

```sh
hatch repo new my-org/my-repo
```

Hatch caches repos after the first clone.

_Tip: Consider adapting the global or project's default [hooks](#hooks) if you always check out the same repo for a task._

**6. Start an agent**

Run an agent from inside a project, task, or repo.

```sh
hatch agent start codex
hatch agent start claude -- --model opus
```

Agents start inside a sandbox by default with read/write access to the current scope; and applying agent-specific profiles.

See [agent sandboxing](#agent-sandboxing) for details.

**7. Cleanup tasks**

Clean up completed tasks:

```sh
hatch workspace clean
```

Hatch lists tasks and preselects ones with closed or merged PRs.

Once submitted, it removes the selected tasks' files locally and deletes their remote branches (see [hooks](#hooks) below to change this).

## Recommended Customizations

### Editor

`hatch task open` uses `VISUAL`, then `EDITOR`, then your platform opener (`open` on macOS, `xdg-open` on Linux).

Add your preferred editor to your shell config:

```sh
export VISUAL='code -n'
# or
export VISUAL='cursor -n'
# or
export EDITOR='vim'
```

### Tab completion

```sh
# Bash
echo 'eval "$(hatch completions bash)"' >> ~/.bashrc

# Zsh
echo 'source <(hatch completions zsh)' >> ~/.zshrc

# Fish
hatch completions fish > ~/.config/fish/completions/hatch.fish
```

### Shell aliases

You can add these to your shell config:

```sh
alias new-project='hatch project new'
alias new-task='hatch task new'
alias new-repo='hatch repo new'
alias open-task='hatch task open'
alias start-agent='hatch agent start'
```

### Ignore AI agent files

Hatch generates AI agent files inside each repo to automatically include project and workspace prompts. Add this to your `~/.gitignore_global`:

```gitignore
CLAUDE.local.md
AGENTS.override.md
```

### Hooks

Hooks define the behavior of the corresponding CLI commands. Change them if you want to add or remove behavior.

Hooks are shell scripts in `.hatch/hooks`:

- Workspace hooks define the default behavior.
- Project hooks override workspace hooks.
- A non-zero hook exit code stops the parent command.
- Edit `<hook>.sh` to customize behavior.

Hatch also writes `<hook>.default` copies in the workspace hooks directory. These contain Hatch's bundled defaults and are refreshed by workspace-aware commands. Hatch upgrades `<hook>.sh` only while it still matches the previous bundled default.

Available hook files:

| Hook             | Runs for                                                                      |
| ---------------- | ----------------------------------------------------------------------------- |
| `agent_start.sh` | `hatch agent start`                                                           |
| `project_new.sh` | `hatch project new`                                                           |
| `repo_new.sh`    | `hatch repo new`                                                              |
| `repo_delete.sh` | `hatch workspace clean` or `hatch project clean` when removing task repos     |
| `task_new.sh`    | `hatch task new`                                                              |
| `task_open.sh`   | `hatch task open`, and after `hatch task new` unless Hatch is non-interactive |

## Development Tasks

To build from source, install:

- [`mise`](https://github.com/jdx/mise)

And then run from this directory:

```sh
mise trust
mise install
mise run install
```

The install task builds the Rust CLI and installs it at `~/.local/bin/hatch`.
