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

# Disable pathname expansion while parsing default-repos.txt.
set -f

# Check out repos listed in a default-repos.txt file.
hatch_checkout_default_repos() {
  file="$1"
  if [ ! -f "$file" ]; then
    return 1
  fi
  did_checkout=0
  while IFS= read -r line || [ -n "$line" ]; do
    set -- $line
    case "${1:-}" in
      ""|\#*)
        continue
        ;;
      *)
        did_checkout=1
        ;;
    esac
    repo="$1"
    base_branch="${2:-}"
    case "$base_branch" in
      \#*)
        base_branch=""
        ;;
    esac
    if [ -n "$base_branch" ]; then
      hatch repo new "$repo" --task-path "$task_path" --base-branch "$base_branch"
    else
      hatch repo new "$repo" --task-path "$task_path"
    fi
  done < "$file"
  [ "$did_checkout" -eq 1 ]
}

# Check out project defaults when present; otherwise use workspace defaults.
hatch_checkout_default_repos "$project_default_repos" || hatch_checkout_default_repos "$workspace_default_repos"
