#!/usr/bin/env bash
set -euo pipefail

# Path guard helpers.

retro_ha_realpath_norm() {
  # Normalize a path like `realpath -m`.
  # - Does not require the path to exist.
  # - Does not resolve symlinks.
  retro_ha_realpath_m "$1"
}

retro_ha_path_is_under() {
  # Returns 0 if candidate is equal to base or strictly under base.
  # Both paths are normalized with retro_ha_realpath_m.
  local base_raw="$1"
  local candidate_raw="$2"

  local base
  base="$(retro_ha_realpath_norm "$base_raw")"
  local candidate
  candidate="$(retro_ha_realpath_norm "$candidate_raw")"

  if [[ "$candidate" == "$base" ]]; then
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-path:is-under-equal"
    fi
    return 0
  fi

  # Ensure base '/' behaves sensibly.
  if [[ "$base" == "/" ]]; then
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-path:is-under-base-root"
    fi
    return 0
  fi

  if [[ "$candidate" == "$base"/* ]]; then
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-path:is-under-child"
    fi
    return 0
  fi

  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-path:is-under-false"
  fi
  return 1
}
