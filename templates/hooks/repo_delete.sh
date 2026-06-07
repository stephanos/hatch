#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

. "$HATCH_HOOK_LIB_DIR/hatch.sh"

repo_path="$(hatch_arg_value --required --repo-path "$@")"

# Move into the repo to inspect the current branch.
cd "$repo_path"
branch="$(git branch --show-current)"
if [ -z "$branch" ]; then
  exit 0
fi

# In dry-run mode, just report the candidate instead of deleting.
if hatch_has_flag --dry-run "$@"; then
  echo "DELETABLE"
  exit 0
fi

# Delete remote branch (if present) and remove local repo directory.
if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  git push --delete origin "$branch" || exit 0
fi
rm -rf "$repo_path"
