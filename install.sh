#!/bin/sh
set -eu

repo="${HATCH_REPO:-stephanos/hatch}"
install_dir="${HATCH_INSTALL_DIR:-$HOME/.local/bin}"
tmp_dir="$(mktemp -d)"
mount_dir=""

cleanup() {
  if [ -n "$mount_dir" ] && mount | grep -q "on $mount_dir "; then
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
os_pattern="$os"
case "$os" in
  darwin)
    os_pattern="darwin|macos"
    ;;
  linux)
    os_pattern="linux"
    ;;
esac
arch="$(uname -m)"
case "$arch" in
  x86_64 | amd64)
    arch="x86_64"
    ;;
  arm64 | aarch64)
    arch="arm64"
    ;;
  *)
    echo "unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

if [ ! -f "$tmp_dir/release.json" ]; then
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" -o "$tmp_dir/release.json"
fi

download_url="$(grep -o '"browser_download_url": "[^"]*"' "$tmp_dir/release.json" \
  | sed 's/^.*"//;s/"$//' \
  | grep -Ei "$os_pattern" \
  | grep -i "$arch" \
  | head -n 1)"

if [ -z "$download_url" ]; then
  echo "could not find matching release artifact for $os/$arch" >&2
  echo "available downloads:" >&2
  grep -o '"browser_download_url": "[^"]*"' "$tmp_dir/release.json" | sed 's/^.*"//;s/"$//' >&2
  exit 1
fi

artifact="$tmp_dir/artifact"
curl -fsSL "$download_url" -o "$artifact"

if printf '%s' "$download_url" | grep -Eq '\.tar\.gz$|\.tgz$'; then
  extract_dir="$tmp_dir/extract"
  mkdir -p "$extract_dir"
  tar -xzf "$artifact" -C "$extract_dir"
  bin_path="$(find "$extract_dir" -type f \( -name hatch -o -name 'hatch-*' \) | head -n 1)"
  if [ -z "$bin_path" ]; then
    bin_path="$(find "$extract_dir" -type f -name 'hatch-*' | head -n 1)"
  fi
  [ -n "$bin_path" ] || { echo "downloaded archive does not include a hatch executable" >&2; exit 1; }
elif printf '%s' "$download_url" | grep -Eq '\.zip$'; then
  extract_dir="$tmp_dir/extract"
  mkdir -p "$extract_dir"
  unzip -q "$artifact" -d "$extract_dir"
  bin_path="$(find "$extract_dir" -type f \( -name hatch -o -name 'hatch-*' \) | head -n 1)"
  if [ -z "$bin_path" ]; then
    bin_path="$(find "$extract_dir" -type f -name 'hatch-*' | head -n 1)"
  fi
  [ -n "$bin_path" ] || { echo "downloaded archive does not include a hatch executable" >&2; exit 1; }
elif printf '%s' "$download_url" | grep -Eq '\.dmg$'; then
  if ! command -v hdiutil >/dev/null 2>&1; then
    echo "hdiutil is required to install from a DMG" >&2
    exit 1
  fi
  mount_dir="$tmp_dir/mount"
  mkdir -p "$mount_dir"
  hdiutil attach "$artifact" -nobrowse -readonly -mountpoint "$mount_dir" >/dev/null
  bin_path="$(find "$mount_dir" -type f \( -name hatch -o -name 'hatch-*' \) | head -n 1)"
  [ -n "$bin_path" ] || { echo "downloaded disk image does not include a hatch executable" >&2; exit 1; }
else
  bin_path="$artifact"
fi

mkdir -p "$install_dir"
chmod +x "$bin_path"
install -m 0755 "$bin_path" "$install_dir/hatch"
echo "installed hatch to $install_dir/hatch"
