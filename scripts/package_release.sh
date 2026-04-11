#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_PATH="$DIST_DIR/Hatch.app"

eval "$(bash "$ROOT/scripts/resolve_version.sh")"

bash "$ROOT/scripts/build_app_bundle.sh"

ARCHIVE_PATH="$DIST_DIR/hatch-${HATCH_VERSION}.zip"
rm -f "$ARCHIVE_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

printf 'Packaged %s\n' "$ARCHIVE_PATH"
