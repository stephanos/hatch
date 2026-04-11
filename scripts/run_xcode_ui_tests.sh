#!/usr/bin/env bash

set -euo pipefail

attempts=4
delay_seconds=5
log_file="$(mktemp -t hatch-xcode-ui-test.XXXXXX.log)"
derived_data_root=".build/xcode-derived-data"
readonly xcode_arguments=("$@")
trap 'rm -f "$log_file"' EXIT

mkdir -p "$derived_data_root"

cleanup_ui_test_processes() {
  pkill -f "HatchUITests-Runner" || true
  pkill -f "dev.stephanos.hatch" || true
  pgrep -f "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project hatch.xcodeproj" \
    | xargs -r kill >/dev/null 2>&1 || true
}

run_tests() {
  local attempt="$1"
  local derived_data_path="${derived_data_root}/attempt-${attempt}"
  rm -rf "$derived_data_path"

  xcodebuild test \
    -project hatch.xcodeproj \
    -scheme hatch \
    -destination 'platform=macOS,arch=arm64' \
    -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1 \
    -derivedDataPath "$derived_data_path" \
    "${xcode_arguments[@]}" \
    2>&1 | tee "$log_file"
  return "${PIPESTATUS[0]}"
}

for ((attempt = 1; attempt <= attempts; attempt++)); do
  cleanup_ui_test_processes

  if run_tests "$attempt"; then
    exit 0
  fi

  if (( attempt == attempts )); then
    exit 1
  fi

  if rg -q "Authentication canceled|Canceled by user" "$log_file"; then
    exit 1
  fi

  if ! rg -q "Timed out while enabling automation mode|Failed to initialize for UI testing|Lost connection to testmanagerd" "$log_file"; then
    exit 1
  fi

  cleanup_ui_test_processes
  sleep "$delay_seconds"
done
