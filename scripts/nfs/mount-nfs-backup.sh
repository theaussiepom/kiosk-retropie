#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "mount-nfs-backup [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

main() {
  export RETRO_HA_LOG_PREFIX="mount-nfs-backup"

  local enabled="${RETRO_HA_SAVE_BACKUP_ENABLED:-0}"
  if [[ "$enabled" != "1" ]]; then
    cover_path "mount-nfs-backup:disabled"
    exit 0
  fi

  local server="${RETRO_HA_SAVE_BACKUP_NFS_SERVER:-${NFS_SERVER:-}}"
  local export_path="${RETRO_HA_SAVE_BACKUP_NFS_PATH:-${NFS_PATH:-}}"
  local mount_point="${RETRO_HA_SAVE_BACKUP_DIR:-$(retro_ha_path /mnt/retro-ha-backup)}"
  local mount_opts="${RETRO_HA_SAVE_BACKUP_NFS_MOUNT_OPTIONS:-rw}"

  if [[ -z "$server" || -z "$export_path" ]]; then
    cover_path "mount-nfs-backup:not-configured"
    log "Backup NFS not configured (set RETRO_HA_SAVE_BACKUP_NFS_SERVER/PATH or NFS_SERVER/NFS_PATH); skipping"
    exit 0
  fi

  run_cmd mkdir -p "$mount_point"
  if mountpoint -q "$mount_point"; then
    cover_path "mount-nfs-backup:already-mounted"
    exit 0
  fi

  log "Mounting ${server}:${export_path} -> ${mount_point} (opts: ${mount_opts})"
  cover_path "mount-nfs-backup:mount-attempt"
  if ! run_cmd mount -t nfs -o "$mount_opts" "${server}:${export_path}" "$mount_point"; then
    cover_path "mount-nfs-backup:mount-failed"
    log "Mount failed; continuing without backup"
    exit 0
  fi

  cover_path "mount-nfs-backup:mount-success"
}

if ! retro_ha_is_sourced; then
  main "$@"
fi
