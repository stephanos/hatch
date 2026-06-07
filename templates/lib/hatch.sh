# hatch-hook-lib-version: 1

hatch_lib_dir="${HATCH_HOOK_LIB_DIR:-}"
if [ -z "$hatch_lib_dir" ]; then
  printf 'HATCH_HOOK_LIB_DIR is required before sourcing hatch.sh.\n' >&2
  return 1 2>/dev/null || exit 1
fi

. "$hatch_lib_dir/args.sh"
. "$hatch_lib_dir/path.sh"
. "$hatch_lib_dir/repo.sh"

hatch_workspace_root() {
  "${HATCH_BIN:-hatch}" workspace root
}
