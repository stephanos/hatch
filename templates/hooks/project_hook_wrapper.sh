#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

# Delegate project hooks to the matching workspace hook by default.
exec "${HATCH_BIN:-hatch}" hook workspace {HOOK_NAME} "$@"
