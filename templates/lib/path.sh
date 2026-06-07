hatch_basename() {
  path="$1"
  path="${path%/}"
  printf '%s\n' "${path##*/}"
}
