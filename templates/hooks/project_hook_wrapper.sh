#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

hatch_bin="${HATCH_BIN:-hatch}"
if command -v "$hatch_bin" >/dev/null 2>&1 && "$hatch_bin" hook workspace --help >/dev/null 2>&1; then
  exec "$hatch_bin" hook workspace {HOOK_NAME} "$@"
fi

current_dir="$(CDPATH= cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
workspace_root="$(dirname "$(dirname "$(dirname "$current_dir")")")"
workspace_hook="$workspace_root/.hatch/hooks/{HOOK_NAME}.sh"

if [ ! -f "$workspace_hook" ]; then
  printf '%s\n' "missing workspace hook: $workspace_hook" >&2
  exit 1
fi

exec sh "$workspace_hook" "$@"
