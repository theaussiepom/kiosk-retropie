#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "save-backup [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=scripts/lib/backup.sh
source "$LIB_DIR/backup.sh"

main() {
  export KIOSK_RETROPIE_LOG_PREFIX="save-backup"

  local enabled="${RETROPIE_SAVE_BACKUP_ENABLED:-${KIOSK_RETROPIE_SAVE_BACKUP_ENABLED:-1}}"
  if [[ "$enabled" != "1" ]]; then
    cover_path "save-backup:disabled"
    exit 0
  fi

  # Never write during gameplay.
  if systemctl is-active --quiet retro-mode.service; then
    cover_path "save-backup:retro-active"
    log "Retro mode active; skipping backup"
    exit 0
  fi

  local user="retropi"
  local saves_dir
  saves_dir="$(kiosk_retropie_path /var/lib/kiosk-retropie/retropie/saves)"
  local states_dir
  states_dir="$(kiosk_retropie_path /var/lib/kiosk-retropie/retropie/states)"

  local mount_point
  mount_point="$(kiosk_retropie_path /mnt/kiosk-retropie-nfs)"

  local hostname_default
  hostname_default="${HOSTNAME:-}"
  if [[ -z "$hostname_default" ]] && command -v hostname > /dev/null 2>&1; then
    hostname_default="$(hostname -s 2> /dev/null || hostname 2> /dev/null || true)"
  fi
  if [[ -z "$hostname_default" ]]; then
    hostname_default="kiosk-retropie"
  fi

  local backup_root="$mount_point/backups"
  local backup_subdir="${RETROPIE_SAVE_BACKUP_SUBDIR:-${KIOSK_RETROPIE_SAVE_BACKUP_SUBDIR:-$hostname_default}}"
  local delete="${RETROPIE_SAVE_BACKUP_DELETE:-${KIOSK_RETROPIE_SAVE_BACKUP_DELETE:-0}}"

  # Ensure NFS is mounted (fails closed on missing config; fail-open if mount fails).
  run_cmd "$SCRIPT_DIR/mount-nfs.sh"

  if ! mountpoint -q "$mount_point"; then
    cover_path "save-backup:not-mounted"
    log "Backup mount not available at $mount_point; skipping"
    exit 0
  fi

  if ! command -v rsync > /dev/null 2>&1; then
    cover_path "save-backup:rsync-missing"
    log "rsync not installed; skipping"
    exit 0
  fi

  run_cmd mkdir -p "$backup_root/$backup_subdir"
  run_cmd chown -R "$user:$user" "$backup_root/$backup_subdir" || true

  local -a args
  local arg
  while IFS= read -r arg; do
    [[ -n "$arg" ]] || continue
    args+=("$arg")
  done <<< "$(save_backup_rsync_args "$delete")"

  if [[ "$delete" == "1" ]]; then
    cover_path "save-backup:delete-enabled"
  fi

  local item
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue

    local label src dest
    IFS=$'\t' read -r label src dest <<< "$item"

    case "$label" in
      saves)
        cover_path "save-backup:backup-saves"
        log "Backing up saves: $src -> $dest (delete=$delete)"
        ;;
      states)
        cover_path "save-backup:backup-states"
        log "Backing up states: $src -> $dest (delete=$delete)"
        ;;
      *)
        continue
        ;;
    esac

    run_cmd mkdir -p "$dest"
    run_cmd rsync "${args[@]}" "$src/" "$dest/" || true
  done <<< "$(save_backup_plan "$saves_dir" "$states_dir" "$backup_root" "$backup_subdir")"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
