#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

. "$HATCH_HOOK_LIB_DIR/hatch.sh"

task_path="$(hatch_arg_value --required --task-path "$@")"

if [ "${HATCH_NON_INTERACTIVE:-0}" = "1" ]; then
  printf 'would open %s with default editor\n' "$task_path"
  exit 0
fi

if [ -n "${VISUAL+x}" ] && [ -n "$VISUAL" ]; then
  printf 'opening %s with VISUAL %s\n' "$task_path" "$VISUAL"
  sh -c "$VISUAL \"$task_path\""
  exit $?
fi

if [ -n "${EDITOR+x}" ] && [ -n "$EDITOR" ]; then
  printf 'opening %s with EDITOR %s\n' "$task_path" "$EDITOR"
  sh -c "$EDITOR \"$task_path\""
  exit $?
fi

if command -v open >/dev/null 2>&1; then
  printf 'opening %s with open\n' "$task_path"
  open "$task_path"
  exit $?
fi

if command -v xdg-open >/dev/null 2>&1; then
  printf 'opening %s with xdg-open\n' "$task_path"
  xdg-open "$task_path"
  exit $?
fi

printf 'Set VISUAL or EDITOR to open %s\n' "$task_path" >&2
exit 1
