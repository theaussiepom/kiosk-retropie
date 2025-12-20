#!/usr/bin/env bash
set -euo pipefail

# Generic list helpers.

split_list() {
  # Split a comma/space separated list into newline-separated tokens.
  # Usage: split_list "$VAR"
  local s="${1:-}"
  if [[ -z "$s" ]]; then
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-list:split-empty"
    fi
    return 0
  fi

  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-list:split-nonempty"
  fi
  s="${s//,/ }"
  # shellcheck disable=SC2086
  for item in $s; do
    printf '%s\n' "$item"
  done
}

in_list() {
  local needle="$1"
  shift
  local x
  for x in "$@"; do
    if [[ "$x" == "$needle" ]]; then
      if declare -F cover_path > /dev/null 2>&1; then
        cover_path "lib-list:in-list-true"
      fi
      return 0
    fi
  done
  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-list:in-list-false"
  fi
  return 1
}
