#!/usr/bin/env bash
set -euo pipefail

# Save/state backup helpers.

save_backup_rsync_args() {
  # Emit rsync args one-per-line for easy array building.
  # Usage: save_backup_rsync_args <delete_flag>
  local delete_flag="${1:-0}"

  if declare -F cover_path > /dev/null 2>&1; then
    if [[ "$delete_flag" == "1" ]]; then
      cover_path "lib-backup:rsync-args-delete"
    else
      cover_path "lib-backup:rsync-args-no-delete"
    fi
  fi

  printf '%s\n' -a --info=stats2 --human-readable
  if [[ "$delete_flag" == "1" ]]; then
    printf '%s\n' --delete
  fi
}

save_backup_plan() {
  # Emit planned backup items one-per-line:
  #   <label>\t<src_dir>\t<dest_dir>
  # Only emits entries for src dirs that exist.
  local saves_dir="$1"
  local states_dir="$2"
  local backup_root="$3"
  local backup_subdir="$4"

  local base_dest
  base_dest="${backup_root}/${backup_subdir}"

  local emitted=0

  if [[ -d "$saves_dir" ]]; then
    emitted=1
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-backup:plan-saves"
    fi
    printf 'saves\t%s\t%s\n' "$saves_dir" "${base_dest}/saves"
  fi

  if [[ -d "$states_dir" ]]; then
    if [[ "$emitted" == "1" ]]; then
      if declare -F cover_path > /dev/null 2>&1; then
        cover_path "lib-backup:plan-both"
      fi
    else
      if declare -F cover_path > /dev/null 2>&1; then
        cover_path "lib-backup:plan-states"
      fi
    fi
    printf 'states\t%s\t%s\n' "$states_dir" "${base_dest}/states"
  fi

  if [[ "$emitted" == "0" ]]; then
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-backup:plan-none"
    fi
  fi
}
