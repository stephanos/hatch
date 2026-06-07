#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
install_dir="$HOME/.local/bin"
install_path="$install_dir/hatch"

cd "$root"
cargo build --release --bin hatch
install -d "$install_dir"
install -m 0755 target/release/hatch "$install_path"
echo "Installed CLI $install_path"
