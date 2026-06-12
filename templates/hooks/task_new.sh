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
checkout_default_repo() {
  repo="$1"
  base_branch="$2"
  if [ -n "$base_branch" ]; then
    hatch repo new "$repo" --base-branch "$base_branch"
  else
    hatch repo new "$repo"
  fi
}

# Check out project defaults when present; otherwise use workspace defaults.
default_repos="$(hatch_default_repos_file "$project_default_repos" "$workspace_default_repos")" || exit 0
tab="$(printf '\t')"
hatch_default_repo_entries "$default_repos" | while IFS="$tab" read -r repo base_branch; do
  checkout_default_repo "$repo" "$base_branch" || exit 1
done
