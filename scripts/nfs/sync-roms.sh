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
  export KIOSK_RETROPIE_LOG_PREFIX="sync-roms"

  local mount_point
  mount_point="$(kiosk_retropie_path /mnt/kiosk-retropie-nfs)"
  local dest_dir
  dest_dir="$(kiosk_retropie_path /var/lib/kiosk-retropie/retropie/roms)"
  local rsync_delete="${RETROPIE_ROMS_SYNC_DELETE:-${KIOSK_RETROPIE_ROMS_SYNC_DELETE:-0}}"
  local dest_owner="${RETROPIE_ROMS_OWNER:-${KIOSK_RETROPIE_ROMS_OWNER:-retropi:retropi}}"
  local systems_allow="${RETROPIE_ROMS_SYSTEMS:-${KIOSK_RETROPIE_ROMS_SYSTEMS:-}}"
  local systems_exclude="${RETROPIE_ROMS_EXCLUDE_SYSTEMS:-${KIOSK_RETROPIE_ROMS_EXCLUDE_SYSTEMS:-}}"

  if [[ -n "${RETROPIE_NFS_ROMS_SUBDIR:-${KIOSK_RETROPIE_NFS_ROMS_SUBDIR:-}}" ]]; then
    cover_path "sync-roms:legacy-subdir-ignored"
    log "KIOSK_RETROPIE_NFS_ROMS_SUBDIR is deprecated and ignored; use the standard share layout under NFS_SERVER instead"
  fi

  # Ensure NFS is mounted (fails closed on missing config; fail-open if mount fails).
  run_cmd "$SCRIPT_DIR/mount-nfs.sh"

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

  local src="$mount_point/roms"

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
  # If RETROPIE_ROMS_SYSTEMS (or legacy KIOSK_RETROPIE_ROMS_SYSTEMS) is set, only those system directories are synced.
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

if ! kiosk_retropie_is_sourced; then
  main "$@"
fi
