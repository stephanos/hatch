hatch_arg_value() {
  required=0
  if [ "${1:-}" = "--required" ]; then
    required=1
    shift
  fi
  name="$1"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      "$name")
        value="${2:-}"
        if [ "$required" -eq 1 ] && [ -z "$value" ]; then
          hook="${0##*/}"
          hook="${hook%.sh}"
          printf '%s requires %s.\n' "$hook" "$name" >&2
          exit 1
        fi
        printf '%s\n' "$value"
        return 0
        ;;
      --)
        break
        ;;
      *)
        shift
        ;;
    esac
  done
  if [ "$required" -eq 1 ]; then
    hook="${0##*/}"
    hook="${hook%.sh}"
    printf '%s requires %s.\n' "$hook" "$name" >&2
    exit 1
  fi
  return 1
}

hatch_has_flag() {
  name="$1"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      "$name")
        return 0
        ;;
      --)
        return 1
        ;;
      *)
        shift
        ;;
    esac
  done
  return 1
}
