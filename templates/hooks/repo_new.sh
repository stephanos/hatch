#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

# Load hook helpers.
. "$HATCH_HOOK_LIB_DIR/hatch.sh"

# Read hook inputs.
workspace_root="$(hatch_workspace_root)"
task_path="$(hatch_arg_value --required --task-path "$@")"
clone_url="$(hatch_arg_value --required --clone-url "$@")"
repo_path="$(hatch_arg_value --required --repo-path "$@")"
base_branch="$(hatch_arg_value --base-branch "$@")"

# Build the task branch name.
task_name="$(hatch_basename "$task_path")"
if [ -z "$task_name" ]; then
  printf 'could not infer branch name from %s\n' "$task_path" >&2
  exit 1
fi
github_user="$(gh api user --jq .login 2>/dev/null || true)"
if [ -n "$github_user" ]; then
  branch="$github_user/$task_name"
else
  branch="$task_name"
fi

# Prepare the shared repo cache.
repo_cache_root="$workspace_root/.hatch/repos"
mkdir -p "$repo_cache_root" || exit 1
cache_repo="$(hatch_repo_cache_path "$repo_cache_root" "$clone_url")"

if [ ! -d "$cache_repo/.git" ]; then
  printf 'cloning %s\n' "$clone_url" >&2
fi
if ! hatch_ensure_repo_cache "$cache_repo" "$clone_url"; then
  if ! git -C "$cache_repo" show-ref --verify >/dev/null 2>&1; then
    printf 'failed to prepare cached repo for %s\n' "$clone_url" >&2
    exit 1
  fi
fi

# Create the task checkout.
cd "$task_path" || exit 1
rm -rf "$repo_path"
git clone "$cache_repo" "$repo_path" || exit 1
git -C "$repo_path" remote set-url origin "$clone_url" || exit 1
hatch_checkout_branch "$repo_path" "$branch" "$base_branch"

# Write repo-local agent instruction forwarding files.
printf '@../AGENTS.md\n' > "$repo_path/AGENTS.override.md"
if [ -f "$repo_path/AGENTS.md" ]; then
  printf '@AGENTS.md\n' >> "$repo_path/AGENTS.override.md"
fi
printf '@AGENTS.override.md\n' > "$repo_path/CLAUDE.local.md"
if [ -f "$repo_path/CLAUDE.md" ]; then
  printf '@CLAUDE.md\n' >> "$repo_path/CLAUDE.local.md"
fi
