#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "sync-roms [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

# shellcheck source=scripts/lib/list.sh
source "$LIB_DIR/list.sh"

main() {
  export RETRO_HA_LOG_PREFIX="sync-roms"

  local mount_point="${RETRO_HA_NFS_MOUNT_POINT:-$(retro_ha_path /mnt/retro-ha-roms)}"
  local source_subdir="${RETRO_HA_NFS_ROMS_SUBDIR:-}"
  local dest_dir="${RETRO_HA_ROMS_DIR:-$(retro_ha_path /var/lib/retro-ha/retropie/roms)}"
  local rsync_delete="${RETRO_HA_ROMS_SYNC_DELETE:-0}"
  local dest_owner="${RETRO_HA_ROMS_OWNER:-retropi:retropi}"
  local systems_allow="${RETRO_HA_ROMS_SYSTEMS:-}"
  local systems_exclude="${RETRO_HA_ROMS_EXCLUDE_SYSTEMS:-}"

  # Ensure NFS is mounted (no-op if not configured / unavailable)
  run_cmd "$SCRIPT_DIR/mount-nfs.sh" || true

  if ! command -v rsync > /dev/null 2>&1; then
    cover_path "sync-roms:rsync-missing"
    log "rsync not installed; skipping"
    exit 0
  fi

  if ! mountpoint -q "$mount_point"; then
    cover_path "sync-roms:not-mounted"
    log "NFS not mounted at $mount_point; skipping"
    exit 0
  fi

  local src="$mount_point"
  if [[ -n "$source_subdir" ]]; then
    cover_path "sync-roms:with-subdir"
    src="$mount_point/$source_subdir"
  fi

  if [[ ! -d "$src" ]]; then
    cover_path "sync-roms:src-missing"
    log "Source path not found on NFS: $src; skipping"
    exit 0
  fi

  run_cmd mkdir -p "$dest_dir"

  local -a args
  args=(-a --info=stats2 --human-readable)
  if [[ "$rsync_delete" == "1" ]]; then
    cover_path "sync-roms:delete-enabled"
    args+=(--delete)
  fi

  log "Syncing ROMs: $src/ -> $dest_dir/ (delete=$rsync_delete)"

  # Prefer RetroPie layout: roms/<system>/...
  # If RETRO_HA_ROMS_SYSTEMS is set, only those system directories are synced.
  # Otherwise, all top-level directories under the source are synced.
  local -a allowlist=()
  local -a excludelist=()
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    allowlist+=("$item")
  done <<< "$(split_list "$systems_allow")"
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    excludelist+=("$item")
  done <<< "$(split_list "$systems_exclude")"

  local -a systems=()
  if [[ ${#allowlist[@]} -gt 0 ]]; then
    cover_path "sync-roms:allowlist"
    systems=("${allowlist[@]}")
  else
    cover_path "sync-roms:discover"
    # Discover system directories on the share.
    local entry
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      entry="${entry##*/}"
      [[ -d "$src/$entry" ]] || continue
      systems+=("$entry")
    done <<< "$(find "$src" -mindepth 1 -maxdepth 1 -type d -print 2> /dev/null | sort)"
  fi

  local system
  for system in "${systems[@]}"; do
    [[ -n "$system" ]] || continue
    if [[ ${#excludelist[@]} -gt 0 ]] && in_list "$system" "${excludelist[@]}"; then
      cover_path "sync-roms:excluded"
      continue
    fi
    if [[ ! -d "$src/$system" ]]; then
      cover_path "sync-roms:missing-system"
      log "Skipping missing system dir on NFS: $src/$system"
      continue
    fi
    run_cmd mkdir -p "$dest_dir/$system"
    run_cmd rsync "${args[@]}" "$src/$system/" "$dest_dir/$system/"
  done

  # Ensure the retropi user can read ROMs in Retro mode.
  if command -v chown > /dev/null 2>&1; then
    cover_path "sync-roms:chown"
    run_cmd chown -R "$dest_owner" "$dest_dir" || true
  fi
}

if ! retro_ha_is_sourced; then
  main "$@"
fi
