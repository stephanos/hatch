#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_v_prefix() {
  local value="$1"
  printf '%s' "${value#v}"
}

is_semver_like() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]
}

resolve_git_tag() {
  git -C "$ROOT" describe --tags --exact-match 2>/dev/null || true
}

resolve_latest_tag() {
  git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || true
}

version="${HATCH_VERSION:-}"
version="$(trim "$version")"

if [[ -z "$version" ]]; then
  version="$(strip_v_prefix "$(resolve_git_tag)")"
fi

if [[ -z "$version" ]]; then
  version="$(strip_v_prefix "$(resolve_latest_tag)")"
fi

if [[ -z "$version" ]]; then
  version="0.1.0"
fi

if ! is_semver_like "$version"; then
  printf 'resolved app version must look like x.y or x.y.z, got: %s\n' "$version" >&2
  exit 1
fi

build_version="${HATCH_BUILD_VERSION:-}"
build_version="$(trim "$build_version")"

if [[ -z "$build_version" ]]; then
  build_version="$version"
fi

if [[ ! "$build_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  printf 'resolved build version must contain only digits and dots, got: %s\n' "$build_version" >&2
  exit 1
fi

printf 'HATCH_VERSION=%s\n' "$version"
printf 'HATCH_BUILD_VERSION=%s\n' "$build_version"
