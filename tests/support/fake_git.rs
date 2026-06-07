#[derive(Clone, Copy)]
pub enum FakeGit {
    Default,
    Clone,
    CloneWithAgents,
    ParallelClone,
}

pub fn script(kind: FakeGit) -> &'static str {
    match kind {
        FakeGit::Default => DEFAULT,
        FakeGit::Clone => CLONE,
        FakeGit::CloneWithAgents => CLONE_WITH_AGENTS,
        FakeGit::ParallelClone => PARALLEL_CLONE,
    }
}

const DEFAULT: &str = r#"#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "git version 2.45.0"
  exit 0
fi
if [ "$1" = "-C" ] && [ "$3" = "remote" ] && [ "$4" = "get-url" ] && [ "$5" = "origin" ] && [ -f "$2/.origin" ]; then
  cat "$2/.origin"
  exit 0
fi
printf 'unsupported git invocation: %s\n' "$*" >&2
exit 1
"#;

const CLONE: &str = r#"#!/bin/sh
if [ "$1" = "--version" ]; then
  echo 'git version 2.50.1'
  exit 0
fi
if [ -n "$HATCH_GIT_LOG" ]; then
  printf '%s\n' "$*" >> "$HATCH_GIT_LOG"
fi
if [ "$1" = "-C" ]; then
  repo="$2"
  shift 2
  if [ "$1" = "remote" ] && [ "$2" = "set-url" ] && [ "$3" = "origin" ]; then
    printf '%s\n' "$4" > "$repo/.clone_url"
    exit 0
  fi
  if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
    cat "$repo/.origin"
    exit 0
  fi
  if [ "$1" = "show-ref" ]; then
    exit 1
  fi
  if [ "$1" = "fetch" ]; then
    mkdir -p "$repo/.git"
    exit 0
  fi
  if [ "$1" = "symbolic-ref" ] && [ "$2" = "--short" ] && [ "$3" = "refs/remotes/origin/HEAD" ]; then
    printf '%s\n' "origin/main"
    exit 0
  fi
  if [ "$1" = "reset" ]; then
    exit 0
  fi
  if [ "$1" = "checkout" ] && [ "$2" = "--track" ] && [ "$3" = "-b" ]; then
    printf '%s\n' "$4" > "$repo/.branch"
    exit 0
  fi
  if [ "$1" = "checkout" ] && [ "$2" = "--no-track" ] && [ "$3" = "-b" ]; then
    printf '%s\n' "$4" > "$repo/.branch"
    exit 0
  fi
  if [ "$1" = "checkout" ] && [ "$2" = "-b" ]; then
    printf '%s\n' "$3" > "$repo/.branch"
    exit 0
  fi
  if [ "$1" = "config" ]; then
    exit 0
  fi
fi
if [ "$1" = "show-ref" ]; then
  exit 1
fi
if [ "$1" = "checkout" ] && [ "$2" = "--track" ] && [ "$3" = "-b" ]; then
  printf '%s\n' "$4" > ".branch"
  exit 0
fi
if [ "$1" = "checkout" ] && [ "$2" = "--no-track" ] && [ "$3" = "-b" ]; then
  printf '%s\n' "$4" > ".branch"
  exit 0
fi
if [ "$1" = "checkout" ] && [ "$2" = "-b" ]; then
  printf '%s\n' "$3" > ".branch"
  exit 0
fi
if [ "$1" = "clone" ]; then
  mkdir -p "$3/.git"
  if [ -f "$2/.clone_url" ]; then
    cp "$2/.clone_url" "$3/.clone_url"
  else
    printf '%s\n' "$2" > "$3/.clone_url"
  fi
  exit 0
fi
printf 'unsupported git invocation: %s\n' "$*" >&2
exit 1
"#;

const CLONE_WITH_AGENTS: &str = r#"#!/bin/sh
if [ "$1" = "--version" ]; then
  echo 'git version 2.50.1'
  exit 0
fi
if [ -n "$HATCH_GIT_LOG" ]; then
  printf '%s\n' "$*" >> "$HATCH_GIT_LOG"
fi
if [ "$1" = "-C" ]; then
  repo="$2"
  shift 2
  if [ "$1" = "remote" ] && [ "$2" = "set-url" ] && [ "$3" = "origin" ]; then
    printf '%s\n' "$4" > "$repo/.clone_url"
    exit 0
  fi
  if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
    cat "$repo/.origin"
    exit 0
  fi
  if [ "$1" = "show-ref" ]; then
    exit 1
  fi
  if [ "$1" = "fetch" ]; then
    mkdir -p "$repo/.git"
    exit 0
  fi
  if [ "$1" = "symbolic-ref" ] && [ "$2" = "--short" ] && [ "$3" = "refs/remotes/origin/HEAD" ]; then
    printf '%s\n' "origin/main"
    exit 0
  fi
  if [ "$1" = "reset" ]; then
    exit 0
  fi
  if [ "$1" = "checkout" ] && [ "$2" = "--track" ] && [ "$3" = "-b" ]; then
    printf '%s\n' "$4" > "$repo/.branch"
    exit 0
  fi
  if [ "$1" = "checkout" ] && [ "$2" = "--no-track" ] && [ "$3" = "-b" ]; then
    printf '%s\n' "$4" > "$repo/.branch"
    exit 0
  fi
  if [ "$1" = "checkout" ] && [ "$2" = "-b" ]; then
    printf '%s\n' "$3" > "$repo/.branch"
    exit 0
  fi
  if [ "$1" = "config" ]; then
    exit 0
  fi
fi
if [ "$1" = "show-ref" ]; then
  exit 1
fi
if [ "$1" = "checkout" ] && [ "$2" = "--track" ] && [ "$3" = "-b" ]; then
  printf '%s\n' "$4" > ".branch"
  exit 0
fi
if [ "$1" = "checkout" ] && [ "$2" = "--no-track" ] && [ "$3" = "-b" ]; then
  printf '%s\n' "$4" > ".branch"
  exit 0
fi
if [ "$1" = "checkout" ] && [ "$2" = "-b" ]; then
  printf '%s\n' "$3" > ".branch"
  exit 0
fi
if [ "$1" = "clone" ]; then
  mkdir -p "$3/.git"
  if [ -f "$2/.clone_url" ]; then
    cp "$2/.clone_url" "$3/.clone_url"
  else
    printf '%s\n' "$2" > "$3/.clone_url"
  fi
  printf 'Repo-specific guidance\n' > "$3/AGENTS.md"
  printf 'Claude-specific guidance\n' > "$3/CLAUDE.md"
  exit 0
fi
printf 'unsupported git invocation: %s\n' "$*" >&2
exit 1
"#;

const PARALLEL_CLONE: &str = r#"#!/bin/sh
if [ "$1" = "--version" ]; then
  echo 'git version 2.50.1'
  exit 0
fi
if [ -n "$HATCH_GIT_LOG" ]; then
  printf '%s\n' "$*" >> "$HATCH_GIT_LOG"
fi
if [ "$1" = "-C" ]; then
  repo="$2"
  shift 2
  if [ "$1" = "remote" ] && [ "$2" = "set-url" ] && [ "$3" = "origin" ]; then
    printf '%s\n' "$4" > "$repo/.clone_url"
    exit 0
  fi
  if [ "$1" = "show-ref" ]; then
    exit 1
  fi
  if [ "$1" = "fetch" ]; then
    mkdir -p "$repo/.git"
    exit 0
  fi
  if [ "$1" = "symbolic-ref" ] && [ "$2" = "--short" ] && [ "$3" = "refs/remotes/origin/HEAD" ]; then
    printf '%s\n' "origin/main"
    exit 0
  fi
  if [ "$1" = "reset" ]; then
    exit 0
  fi
  if [ "$1" = "checkout" ] && [ "$2" = "--track" ] && [ "$3" = "-b" ]; then
    printf '%s\n' "$4" > "$repo/.branch"
    exit 0
  fi
  if [ "$1" = "checkout" ] && [ "$2" = "--no-track" ] && [ "$3" = "-b" ]; then
    printf '%s\n' "$4" > "$repo/.branch"
    exit 0
  fi
  if [ "$1" = "checkout" ] && [ "$2" = "-b" ]; then
    printf '%s\n' "$3" > "$repo/.branch"
    exit 0
  fi
  if [ "$1" = "config" ]; then
    exit 0
  fi
fi
if [ "$1" = "show-ref" ]; then
  exit 1
fi
if [ "$1" = "checkout" ] && [ "$2" = "--track" ] && [ "$3" = "-b" ]; then
  printf '%s\n' "$4" > ".branch"
  exit 0
fi
if [ "$1" = "checkout" ] && [ "$2" = "--no-track" ] && [ "$3" = "-b" ]; then
  printf '%s\n' "$4" > ".branch"
  exit 0
fi
if [ "$1" = "checkout" ] && [ "$2" = "-b" ]; then
  printf '%s\n' "$3" > ".branch"
  exit 0
fi
if [ "$1" = "clone" ]; then
  mkdir -p "$3/.git"
  if [ -f "$2/.clone_url" ]; then
    cp "$2/.clone_url" "$3/.clone_url"
  else
    printf '%s\n' "$2" > "$3/.clone_url"
  fi
  repo="$(basename "$2")"
  repo="${repo%.git}"
  if [ -z "$repo" ]; then
    repo="$(basename "$3")"
  fi
  marker="${HATCH_PARALLEL_MARKER:?}"
  touch "$marker/${repo}_started"
  if [ "$repo" = "slow" ]; then
    i=0
    while [ ! -f "$marker/fast_started" ]; do
      i=$((i + 1))
      if [ "$i" -gt 50 ]; then
        printf 'fast clone did not start while slow clone was running\n' >&2
        exit 42
      fi
      sleep 0.1
    done
  fi
  exit 0
fi
printf 'unsupported git invocation: %s\n' "$*" >&2
exit 1
"#;
