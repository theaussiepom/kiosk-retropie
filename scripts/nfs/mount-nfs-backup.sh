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
  export KIOSK_RETROPIE_LOG_PREFIX="mount-nfs-backup"

  local enabled="${RETROPIE_SAVE_BACKUP_ENABLED:-${KIOSK_RETROPIE_SAVE_BACKUP_ENABLED:-1}}"
  if [[ "$enabled" != "1" ]]; then
    cover_path "mount-nfs-backup:disabled"
    exit 0
  fi

  if [[ -n "${NFS_SAVE_BACKUP_PATH:-}" || -n "${RETROPIE_SAVE_BACKUP_NFS_PATH:-${KIOSK_RETROPIE_SAVE_BACKUP_NFS_PATH:-}}" ]]; then
    cover_path "mount-nfs-backup:legacy-backup-path-ignored"
    log "Legacy backup NFS path variables are ignored; using NFS_SERVER share layout"
  fi

  cover_path "mount-nfs-backup:delegate"
  run_cmd "$SCRIPT_DIR/mount-nfs.sh"
}

if ! kiosk_retropie_is_sourced; then
  main "$@"
fi
