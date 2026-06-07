#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

. "$HATCH_HOOK_LIB_DIR/hatch.sh"

workspace_root="$(hatch_workspace_root)"
project_path="$(hatch_arg_value --required --project-path "$@")"
task_path="$(hatch_arg_value --required --task-path "$@")"
workspace_default_repos="$workspace_root/.hatch/default-repos.txt"
project_default_repos="$project_path/.hatch/default-repos.txt"

printf '@../AGENTS.md\n' > "$task_path/AGENTS.md"
printf '@AGENTS.md\n' > "$task_path/CLAUDE.md"

set -f

hatch_default_repos_has_entries() {
  file="$1"
  if [ ! -f "$file" ]; then
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    set -- $line
    case "${1:-}" in
      ""|\#*)
        continue
        ;;
      *)
        return 0
        ;;
    esac
  done < "$file"
  return 1
}

default_repos="$workspace_default_repos"
if hatch_default_repos_has_entries "$project_default_repos"; then
  default_repos="$project_default_repos"
fi

if hatch_default_repos_has_entries "$default_repos"; then
  while IFS= read -r line || [ -n "$line" ]; do
    set -- $line
    case "${1:-}" in
      ""|\#*)
        continue
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
  done < "$default_repos"
fi
