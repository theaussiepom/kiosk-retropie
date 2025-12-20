#!/usr/bin/env bash
set -euo pipefail

# Common helpers.

retro_ha__cover_path_raw() {
  # Minimal path coverage recorder that does not depend on record_call/cover_path.
  # Used to instrument this file without recursion.
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

retro_ha_is_sourced() {
  # True if the top-level script is being sourced rather than executed.
  # When called from within a sourced library, BASH_SOURCE[0] is the library path,
  # so we must compare $0 against the *last* stack frame (the entry script).
  local last_index
  last_index=$((${#BASH_SOURCE[@]} - 1))
  if [[ "${BASH_SOURCE[$last_index]}" != "${0}" ]]; then
    retro_ha__cover_path_raw "lib-common:is-sourced-true"
    return 0
  fi
  retro_ha__cover_path_raw "lib-common:is-sourced-false"
  return 1
}

retro_ha_root() {
  # Filesystem root prefix for tests.
  # Use RETRO_HA_ROOT="$TEST_ROOT" to make scripts operate within a fake FS.
  local root="${RETRO_HA_ROOT:-/}"
  # Normalize trailing slash (keep '/' as-is).
  if [[ "$root" != "/" ]]; then
    retro_ha__cover_path_raw "lib-common:root-non-slash"
    root="${root%/}"
  else
    retro_ha__cover_path_raw "lib-common:root-slash"
  fi
  echo "$root"
}

retro_ha_path() {
  # Prefix an absolute path with RETRO_HA_ROOT, if set.
  # Examples:
  #   RETRO_HA_ROOT=/tmp/t && retro_ha_path /etc/foo -> /tmp/t/etc/foo
  #   RETRO_HA_ROOT=/       && retro_ha_path /etc/foo -> /etc/foo
  local abs_path="$1"
  if [[ "$abs_path" != /* ]]; then
    retro_ha__cover_path_raw "lib-common:path-relative"
    echo "$abs_path"
    return 0
  fi

  local root
  root="$(retro_ha_root)"
  if [[ "$root" == "/" ]]; then
    retro_ha__cover_path_raw "lib-common:path-root-slash"
    echo "$abs_path"
  else
    retro_ha__cover_path_raw "lib-common:path-prefixed"
    echo "$root$abs_path"
  fi
}

retro_ha_dirname() {
  # Minimal dirname implementation using bash parameter expansion.
  # - Does not touch the filesystem.
  # - Mirrors `dirname` well enough for our internal use.
  local path="${1:-}"
  if [[ -z "$path" ]]; then
    retro_ha__cover_path_raw "lib-common:dirname-empty"
    echo "."
    return 0
  fi
  # Strip trailing slashes (except when the path is just '/').
  while [[ "$path" != "/" && "$path" == */ ]]; do
    retro_ha__cover_path_raw "lib-common:dirname-trailing-slash"
    path="${path%/}"
  done
  # If there are no slashes, dirname is '.'
  if [[ "$path" != */* ]]; then
    retro_ha__cover_path_raw "lib-common:dirname-no-slash"
    echo "."
    return 0
  fi
  # Remove last path segment.
  path="${path%/*}"
  # Collapse empty to '/'
  if [[ -z "$path" ]]; then
    retro_ha__cover_path_raw "lib-common:dirname-collapse-root"
    path="/"
  else
    retro_ha__cover_path_raw "lib-common:dirname-has-slash"
  fi
  echo "$path"
}

require_cmd() {
  command -v "$1" > /dev/null 2>&1 || die "Missing required command: $1"
}

retro_ha_calls_file() {
  # Where to record side-effecting commands when DRY_RUN is enabled.
  # Tests can set RETRO_HA_CALLS_FILE to a path under $TEST_ROOT.
  echo "${RETRO_HA_CALLS_FILE:-}"
}

retro_ha_calls_file_append() {
  # Optional secondary log file for suite-wide aggregation in tests.
  # If set, every record_call line is also appended here.
  echo "${RETRO_HA_CALLS_FILE_APPEND:-}"
}

record_call() {
  local calls_file
  calls_file="$(retro_ha_calls_file)"
  if [[ -n "$calls_file" ]]; then
    retro_ha__cover_path_raw "lib-common:record-primary"
    mkdir -p "$(retro_ha_dirname "$calls_file")"
    printf '%s\n' "$*" >> "$calls_file"
  else
    retro_ha__cover_path_raw "lib-common:record-primary-none"
  fi

  local calls_file_append
  calls_file_append="$(retro_ha_calls_file_append)"
  if [[ -n "$calls_file_append" ]]; then
    retro_ha__cover_path_raw "lib-common:record-append"
    mkdir -p "$(retro_ha_dirname "$calls_file_append")"
    printf '%s\n' "$*" >> "$calls_file_append"
  else
    retro_ha__cover_path_raw "lib-common:record-append-none"
  fi
}

cover_path() {
  # Record a path ID for branch/path coverage in tests.
  # No-op unless RETRO_HA_PATH_COVERAGE=1.
  if [[ "${RETRO_HA_PATH_COVERAGE:-0}" == "1" ]]; then
    # Prefer writing directly to the suite-wide PATHS file to avoid depending on
    # per-test RETRO_HA_CALLS_FILE(_APPEND) wiring.
    retro_ha__cover_path_raw "$1"
    record_call "PATH $1"
  fi
}

run_cmd() {
  # Run a command, optionally in DRY_RUN mode.
  # If RETRO_HA_DRY_RUN=1, record the call and return success.
  if [[ "${RETRO_HA_DRY_RUN:-0}" == "1" ]]; then
    retro_ha__cover_path_raw "lib-common:run-dry-run"
    record_call "$*"
    return 0
  fi
  retro_ha__cover_path_raw "lib-common:run-exec"
  "$@"
}

retro_ha_realpath_m() {
  # Portable equivalent of: realpath -m <path>
  # - Resolves '.' and '..' without requiring the path to exist.
  # - Does not resolve symlinks (matches 'realpath -m' semantics closely enough for guardrails).
  retro_ha__cover_path_raw "lib-common:realpath-called"
  python3 - "$1" << 'PY'
import os
import sys

p = sys.argv[1]

# If relative, anchor at cwd.
if not os.path.isabs(p):
    p = os.path.join(os.getcwd(), p)

print(os.path.normpath(p))
PY
}

svc_start() {
  run_cmd systemctl start "$@"
}

svc_stop() {
  run_cmd systemctl stop "$@"
}
