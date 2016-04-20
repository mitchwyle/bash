#!/usr/bin/env bash


try() {
  "$@"
  local EXIT_CODE=$?
  local FILE
  if [[ $EXIT_CODE -ne 0 ]]; then
    FILE=$(readlink -m "${BASH_SOURCE[1]}")
    local LINE=${BASH_LINENO[0]}
    log "WARN $FILE: line $LINE: Command \`$*' failed with exit code $EXIT_CODE."
  fi
  return $EXIT_CODE
}
#

log() {
  printf '%(%F %T)T : ' -1
  echo "$*"
}

die() {
  log "$*"
  exit 3
}

