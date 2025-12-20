#!/usr/bin/env bash
set -euo pipefail

# Common helpers.

retro_ha_is_sourced() {
  # True if the top-level script is being sourced rather than executed.
  # When called from within a sourced library, BASH_SOURCE[0] is the library path,
  # so we must compare $0 against the *last* stack frame (the entry script).
  local last_index
  last_index=$((${#BASH_SOURCE[@]} - 1))
  [[ "${BASH_SOURCE[$last_index]}" != "${0}" ]]
}

retro_ha_root() {
  # Filesystem root prefix for tests.
  # Use RETRO_HA_ROOT="$TEST_ROOT" to make scripts operate within a fake FS.
  local root="${RETRO_HA_ROOT:-/}"
  # Normalize trailing slash (keep '/' as-is).
  if [[ "$root" != "/" ]]; then
    root="${root%/}"
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
    echo "$abs_path"
    return 0
  fi

  local root
  root="$(retro_ha_root)"
  if [[ "$root" == "/" ]]; then
    echo "$abs_path"
  else
    echo "$root$abs_path"
  fi
}

retro_ha_dirname() {
  # Minimal dirname implementation using bash parameter expansion.
  # - Does not touch the filesystem.
  # - Mirrors `dirname` well enough for our internal use.
  local path="${1:-}"
  if [[ -z "$path" ]]; then
    echo "."
    return 0
  fi
  # Strip trailing slashes (except when the path is just '/').
  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done
  # If there are no slashes, dirname is '.'
  if [[ "$path" != */* ]]; then
    echo "."
    return 0
  fi
  # Remove last path segment.
  path="${path%/*}"
  # Collapse empty to '/'
  if [[ -z "$path" ]]; then
    path="/"
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
    mkdir -p "$(retro_ha_dirname "$calls_file")"
    printf '%s\n' "$*" >> "$calls_file"
  fi

  local calls_file_append
  calls_file_append="$(retro_ha_calls_file_append)"
  if [[ -n "$calls_file_append" ]]; then
    mkdir -p "$(retro_ha_dirname "$calls_file_append")"
    printf '%s\n' "$*" >> "$calls_file_append"
  fi
}

cover_path() {
  # Record a path ID for branch/path coverage in tests.
  # No-op unless RETRO_HA_PATH_COVERAGE=1.
  if [[ "${RETRO_HA_PATH_COVERAGE:-0}" == "1" ]]; then
    record_call "PATH $1"
  fi
}

run_cmd() {
  # Run a command, optionally in DRY_RUN mode.
  # If RETRO_HA_DRY_RUN=1, record the call and return success.
  if [[ "${RETRO_HA_DRY_RUN:-0}" == "1" ]]; then
    record_call "$*"
    return 0
  fi
  "$@"
}

retro_ha_realpath_m() {
  # Portable equivalent of: realpath -m <path>
  # - Resolves '.' and '..' without requiring the path to exist.
  # - Does not resolve symlinks (matches 'realpath -m' semantics closely enough for guardrails).
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
