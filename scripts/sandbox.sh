#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
sandbox="$root/.sandbox"
config_dir="$sandbox/config"
workspace="$sandbox/workspace"

rm -rf "$sandbox"
mkdir -p "$config_dir" "$workspace"

cat > "$config_dir/config.toml" <<EOF
workspace_root = "$workspace"
EOF

export HATCH_CONFIG_DIR="$config_dir"
export HATCH_NON_INTERACTIVE=1
unset HATCH_TEST_CONFIG_DIR
unset HATCH_TEST_WORKSPACE_ROOT

hatch workspace new --force
hatch project new demo-project >/dev/null
hatch task new demo-project demo-task >/dev/null

cat <<EOF
Sandbox ready. Run 'exit' to leave the sandbox shell.
EOF

cd "$workspace"
exec "${SHELL:-/bin/sh}"
