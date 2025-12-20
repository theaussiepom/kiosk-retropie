#!/usr/bin/env bash
set -euo pipefail

# Logging helpers.

retro_ha__cover_path_raw() {
  [[ "${RETRO_HA_PATH_COVERAGE:-0}" == "1" ]] || return 0

  local path_id="${1:-}"
  [[ -n "$path_id" ]] || return 0

  local path_file="${RETRO_HA_PATHS_FILE:-${RETRO_HA_CALLS_FILE_APPEND:-${RETRO_HA_CALLS_FILE:-}}}"
  [[ -n "$path_file" ]] || return 0

  local dir
  dir="${path_file%/*}"
  if [[ -n "$dir" && "$dir" != "$path_file" ]]; then
    mkdir -p "$dir" 2> /dev/null || true
  fi
  printf 'PATH %s\n' "$path_id" >> "$path_file" 2> /dev/null || true
}

retro_ha_log_prefix() {
  # Allow callers to override the prefix for nicer logs.
  if [[ -n "${RETRO_HA_LOG_PREFIX:-}" ]]; then
    retro_ha__cover_path_raw "lib-logging:prefix-override"
  else
    retro_ha__cover_path_raw "lib-logging:prefix-default"
  fi
  echo "${RETRO_HA_LOG_PREFIX:-retro-ha}"
}

log() {
  retro_ha__cover_path_raw "lib-logging:log"
  echo "$(retro_ha_log_prefix): $*" >&2
}

warn() {
  retro_ha__cover_path_raw "lib-logging:warn"
  echo "$(retro_ha_log_prefix) [warn]: $*" >&2
}

die() {
  retro_ha__cover_path_raw "lib-logging:die"
  echo "$(retro_ha_log_prefix) [error]: $*" >&2
  exit 1
}
