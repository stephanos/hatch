#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="hatch"
APP_BUNDLE_NAME="Hatch"
APP_BUNDLE_ID="dev.stephanos.hatch"
INSTALL_DIR="${APP_INSTALL_DIR:-/Applications}"
CLI_INSTALL_DIR="${CLI_INSTALL_DIR:-$HOME/.local/bin}"
SOURCE_APP="$ROOT/dist/${APP_BUNDLE_NAME}.app"
TARGET_APP="$INSTALL_DIR/${APP_BUNDLE_NAME}.app"
CLI_TARGET="$CLI_INSTALL_DIR/hatch"

bash "$ROOT/scripts/build_app_bundle.sh"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done

  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  fi
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
mkdir -p "$CLI_INSTALL_DIR"
ln -sfn "$TARGET_APP/Contents/MacOS/hatch-cli" "$CLI_TARGET"

echo "Installed $TARGET_APP"
echo "Installed CLI $CLI_TARGET"
open "$TARGET_APP"
