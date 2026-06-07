#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

# Load hook helpers.
. "$HATCH_HOOK_LIB_DIR/hatch.sh"

# Read hook inputs.
repo_path="$(hatch_arg_value --required --repo-path "$@")"

# Resolve the local branch.
branch="$(git -C "$repo_path" branch --show-current)"
if [ -z "$branch" ]; then
  exit 0
fi

# Report cleanup eligibility.
# In dry-run mode, just report the candidate instead of deleting.
if hatch_has_flag --dry-run "$@"; then
  echo "DELETABLE"
  exit 0
fi

# Delete branch and checkout.
# Delete remote branch (if present) and remove local repo directory.
if git -C "$repo_path" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  git -C "$repo_path" push --delete origin "$branch" || exit 0
fi
rm -rf "$repo_path"
