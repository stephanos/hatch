#!/usr/bin/env zsh
typeset -gA compstate=()
compdef() {
  :
}
source {COMPLETION_PATH}
compadd() {
  local display_array=""
  local message=""
  while (( $# > 0 )); do
    case "$1" in
      -d)
        shift
        display_array="$1"
        ;;
      -x)
        shift
        message="$1"
        ;;
    esac
    shift
  done
  if [[ -n "$message" ]]; then
    print -r -- "MESSAGE=$message"
  fi
  if [[ -n "$display_array" ]]; then
    local -a display_entries
    eval "display_entries=(\"\${${display_array}[@]}\")"
    for entry in "${display_entries[@]}"; do
      print -r -- "DISPLAY=$entry"
    done
  fi
}
words=({WORDS_EXPR})
CURRENT={CURRENT}
print -r -- "INSERT_BEFORE=${compstate[insert]}"
_hatch
print -r -- "INSERT_AFTER=${compstate[insert]}"
print -r -- "LIST_AFTER=${compstate[list]}"
