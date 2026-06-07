#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

# Load hook helpers.
. "$HATCH_HOOK_LIB_DIR/hatch.sh"

# Read hook inputs.
workspace_root="$(hatch_workspace_root)"
project_path="$(hatch_arg_value --required --project-path "$@")"
task_path="$(hatch_arg_value --required --task-path "$@")"
workspace_default_repos="$workspace_root/.hatch/default-repos.txt"
project_default_repos="$project_path/.hatch/default-repos.txt"

# Write agent instruction forwarding files.
printf '@../AGENTS.md\n' > "$task_path/AGENTS.md"
printf '@AGENTS.md\n' > "$task_path/CLAUDE.md"

# Check out one default repo.
hatch_checkout_default_repo() {
  repo="$1"
  base_branch="$2"
  if [ -n "$base_branch" ]; then
    hatch repo new "$repo" --task-path "$task_path" --base-branch "$base_branch"
  else
    hatch repo new "$repo" --task-path "$task_path"
  fi
}

# Check out project defaults when present; otherwise use workspace defaults.
hatch_each_default_repo "$project_default_repos" hatch_checkout_default_repo
default_repos_status=$?
if [ "$default_repos_status" -eq 1 ]; then
  hatch_each_default_repo "$workspace_default_repos" hatch_checkout_default_repo
  default_repos_status=$?
fi
if [ "$default_repos_status" -gt 1 ]; then
  exit "$default_repos_status"
fi
