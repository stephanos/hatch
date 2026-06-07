#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

# Load hook helpers.
. "$HATCH_HOOK_LIB_DIR/hatch.sh"

# Read hook inputs.
hatch_bin="${HATCH_BIN:-hatch}"
agent="$(hatch_arg_value --required --agent "$@")"
scope_path="$(hatch_arg_value --required --scope-path "$@")"

# Keep only forwarded agent arguments.
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

# Document sandbox customization.
# Available __agent-exec flags:
#   --profile <ref>       Add a sandbox profile. Repeatable.
#   --registry <url>      Use a custom profile registry.
#   --allow <path>        Allow read/write access to a path. Repeatable.
#   --read <path>         Allow read-only access to a path. Repeatable.
#   --write <path>        Allow write-only access to a path. Repeatable.
#   --block-net           Block network access.
#   --allow-port <port>   Allow a localhost port. Repeatable.
# Args after -- are passed to the agent.

# Launch the requested agent.
case "$agent" in
  codex)
    exec "$hatch_bin" __agent-exec "$agent" \
      --profile always-further/codex \
      --allow "$scope_path" \
      -- "$@"
    ;;
  claude)
    exec "$hatch_bin" __agent-exec "$agent" \
      --profile always-further/claude \
      --allow "$scope_path" \
      -- "$@"
    ;;
  *)
    exec "$hatch_bin" __agent-exec "$agent" \
      --allow "$scope_path" \
      -- "$@"
    ;;
esac
