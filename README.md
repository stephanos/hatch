# hatch

[![release](https://img.shields.io/github/v/release/stephanos/hatch)](https://github.com/stephanos/hatch/releases/latest)

`hatch` is a CLI for task-oriented git workspace management, built for AI-assisted development.

It creates disposable, task-scoped workspaces with isolated repo checkouts and agent context.

## Get Started

**1. Install**

```sh
curl -fsSL https://raw.githubusercontent.com/stephanos/hatch/main/install.sh | sh
```

On macOS, if Gatekeeper reports that the downloaded binary is quarantined, run:

```sh
xattr -dr com.apple.quarantine "$HOME/.local/bin/hatch"
```

**2. Init**

Pass the folder where you want your projects to live. Use `.` for the current directory.

```sh
hatch workspace new ~/Workspace
```

**3. Create projects and tasks**

All tasks are grouped into projects.

```sh
hatch project new my-project
hatch task new my-project my-task
```

Regardless of where you run this from, it'll create `<workspace>/my-project/my-task`.

**4. Work on a task**

To open a task (directory) in your default editor:

```sh
hatch task open my-task
# or
hatch task open https://github.com/acme/web/pull/123
```

This fuzzy matches tasks across all projects, or resolves GitHub PR URLs.

**5. Clone a repo**

Clone a repo and check out its HEAD as a new local branch `<github username>/<task name>`.

```sh
hatch repo new my-org/my-repo
```

After the first clone, Hatch keeps a cache of the repo for faster cloning next time.

_Tip: Consider adapting the global or project's default hooks (see below) if you always check out the same repo for a task._

**6. Start an agent**

Run an agent from inside a workspace, project, or task.

```sh
hatch agent start codex
hatch agent start claude -- --model opus
```

Customize `.hatch/hooks/agent_start.sh` to change how agents are launched or which sandbox capabilities they receive.

**7. Cleanup tasks**

After a while you might accumulate a few completed tasks. To clean them up:

```sh
hatch workspace clean
```

It will present a list of tasks to select; auto-selecting the ones that have closed/merged PRs.

Once submitted, it removes the selected tasks' files locally and deletes their remote branches (see hooks below to change this).

## Recommended Customizations

### Tab completion

```sh
# Bash
echo 'eval "$(hatch completions bash)"' >> ~/.bashrc

# Zsh
echo 'source <(hatch completions zsh)' >> ~/.zshrc

# Fish
hatch completions fish > ~/.config/fish/completions/hatch.fish
```

Carapace can also drive completion if you prefer its shell integration:

```sh
mkdir -p ~/Library/Application\ Support/carapace/specs
hatch completions carapace > ~/Library/Application\ Support/carapace/specs/hatch.yaml
echo 'CARAPACE_UNFILTERED=1 source <(carapace hatch zsh)' >> ~/.zshrc
```

### Shell aliases

You can add these to your shell config:

```sh
alias new-project='hatch project new'
alias new-task='hatch task new'
alias new-repo='hatch repo new'
alias open-task='hatch task open'
```

### Ignore generated AI prompt files

Add this to your `~/.gitignore_global`:

```gitignore
CLAUDE.local.md
AGENTS.override.md
```

### Hooks

Hooks define the behavior of the corresponding CLI commands. Change them if you want to add or remove behavior.

Hooks are shell scripts that live in `.hatch/hooks` in the workspace/project folder.
Any hooks defined in the project folder override hooks in the workspace folder.
A non-zero hook exit code stops the parent command.
Hatch also writes `<hook>.default.sh` copies in the workspace hooks directory. These files contain Hatch's current bundled defaults and are refreshed by workspace-aware commands. Edit `<hook>.sh` to customize behavior; Hatch upgrades it only while it still matches the previous bundled default.

Available hook files:

- `project_new.sh`
- `repo_new.sh`
- `repo_delete.sh`
- `task_new.sh`
- `task_open.sh`
- `agent_start.sh`

Each hook receives named arguments:

- `--project-path`
- `--task-path`
- `--clone-url`
- `--repo-path`
- `--base-branch`
- `--agent`
- `--scope-path`
- `--dry-run`

## Development Tasks

Or to build from source, you need:

- [`mise`](https://github.com/jdx/mise)

And then run from this directory:

```sh
mise trust
mise install
mise run install
```

The install task builds the Rust CLI and installs it at `~/.local/bin/hatch`.
