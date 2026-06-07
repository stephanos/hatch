#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

. "$HATCH_HOOK_LIB_DIR/hatch.sh"

hatch_bin="${HATCH_BIN:-hatch}"
agent="$(hatch_arg_value --required --agent "$@")"
scope_path="$(hatch_arg_value --required --scope-path "$@")"
workspace_root="$(hatch_workspace_root)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      break
      ;;
    *)
      shift
      ;;
  esac
done

"$hatch_bin" __agent-launch "$agent" --workspace-root "$workspace_root" --scope-path "$scope_path" -- "$@"
