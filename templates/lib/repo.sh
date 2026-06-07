hatch_repo_cache_key() {
  source="$1"
  printf '%s\n' "$source" | tr -c 'A-Za-z0-9._-' '_'
}

hatch_repo_cache_path() {
  cache_root="$1"
  source="$2"
  printf '%s/%s\n' "$cache_root" "$(hatch_repo_cache_key "$source")"
}

hatch_update_cached_repo() {
  cache_repo="$1"
  git -C "$cache_repo" fetch --all --prune
  origin_head="$(git -C "$cache_repo" symbolic-ref --short refs/remotes/origin/HEAD)"
  if [ -n "$origin_head" ]; then
    git -C "$cache_repo" reset --hard "origin/${origin_head#origin/}"
  else
    return 0
  fi
}

hatch_ensure_repo_cache() {
  cache_repo="$1"
  source="$2"
  if [ -d "$cache_repo/.git" ]; then
    hatch_update_cached_repo "$cache_repo" || return 1
    return 0
  fi
  if [ -d "$cache_repo" ]; then
    rm -rf "$cache_repo"
  fi
  if git clone "$source" "$cache_repo"; then
    hatch_update_cached_repo "$cache_repo" || return 1
    return 0
  fi
  if [ -d "$cache_repo/.git" ]; then
    hatch_update_cached_repo "$cache_repo" || return 1
    return 0
  fi
  return 1
}

hatch_checkout_branch() {
  repo_path="$1"
  branch="$2"
  base_branch="$3"
  if git -C "$repo_path" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git -C "$repo_path" checkout --track -b "$branch" "origin/$branch" || return 1
  elif [ -n "$base_branch" ]; then
    git -C "$repo_path" checkout --no-track -b "$branch" "origin/$base_branch" || return 1
  else
    git -C "$repo_path" checkout -b "$branch" || return 1
  fi
  git -C "$repo_path" config "branch.$branch.remote" origin || return 1
  git -C "$repo_path" config "branch.$branch.merge" "refs/heads/$branch" || return 1
}

hatch_default_repo_entries() {
  file="$1"
  if [ ! -f "$file" ]; then
    return 1
  fi

  # Disable pathname expansion while parsing default-repos.txt.
  case "$-" in
    *f*)
      restore_glob=0
      ;;
    *)
      restore_glob=1
      set -f
      ;;
  esac

  did_read=0
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
    did_read=1
    printf '%s\t%s\n' "$repo" "$base_branch"
  done < "$file"
  if [ "$restore_glob" -eq 1 ]; then
    set +f
  fi
  [ "$did_read" -eq 1 ]
}

hatch_default_repos_has_entries() {
  hatch_default_repo_entries "$1" >/dev/null
}

hatch_default_repos_file() {
  project_default_repos="$1"
  workspace_default_repos="$2"
  if hatch_default_repos_has_entries "$project_default_repos"; then
    printf '%s\n' "$project_default_repos"
  elif hatch_default_repos_has_entries "$workspace_default_repos"; then
    printf '%s\n' "$workspace_default_repos"
  else
    return 1
  fi
}
