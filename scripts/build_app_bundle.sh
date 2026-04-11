#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="hatch"
APP_BUNDLE_NAME="Hatch"
BUNDLE_DIR="$ROOT/dist/${APP_BUNDLE_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT/Sources/HatchApp/Resources/twemoji-hatching-chick.svg"
ICON_NAME="${APP_NAME}.icns"

cd "$ROOT"

eval "$(bash "$ROOT/scripts/resolve_version.sh")"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BIN_PATH="$BIN_DIR/$APP_NAME"
CLI_BIN_PATH="$BIN_DIR/hatch-cli"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "expected built binary at $BIN_PATH" >&2
  exit 1
fi

if [[ ! -x "$CLI_BIN_PATH" ]]; then
  echo "expected built CLI binary at $CLI_BIN_PATH" >&2
  exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "expected icon source at $ICON_SOURCE" >&2
  exit 1
fi

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
cp "$CLI_BIN_PATH" "$MACOS_DIR/hatch-cli"
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$BUNDLE_DIR"/ \;

ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
ICONSET_DIR="$ICON_TMP/${APP_NAME}.iconset"
BASE_PNG="$ICON_TMP/${APP_NAME}-1024.png"

mkdir -p "$ICONSET_DIR"
qlmanage -t -s 1024 -o "$ICON_TMP" "$ICON_SOURCE" >/dev/null 2>&1
mv "$ICON_TMP/$(basename "$ICON_SOURCE").png" "$BASE_PNG"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$BASE_PNG" \
    --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$ICON_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>hatch</string>
  <key>CFBundleIdentifier</key>
  <string>dev.stephanos.hatch</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>hatch</string>
  <key>CFBundleName</key>
  <string>Hatch</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${HATCH_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${HATCH_BUILD_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

echo "Built $BUNDLE_DIR"
