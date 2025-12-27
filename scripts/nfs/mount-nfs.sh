#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "mount-nfs [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

main() {
  export KIOSK_RETROPIE_LOG_PREFIX="mount-nfs"

  local server_spec="${NFS_SERVER:-}"
  local server=""
  local export_path=""
  local mount_point
  mount_point="$(kiosk_retropie_path /mnt/kiosk-retropie-nfs)"
  local mount_opts="rw"

  # Default export path when NFS_SERVER is a bare host.
  local default_export_path="/export/kiosk-retropie"

  # Back-compat: allow legacy NFS_ROMS_PATH, treating it as the share root.
  # (Deprecated in favor of NFS_SERVER=host:/export/path).
  if [[ -n "${NFS_ROMS_PATH:-}" ]]; then
    cover_path "mount-nfs:legacy-roms-path"
    log "Using legacy NFS_ROMS_PATH as share root; prefer NFS_SERVER=host:/export/path"
    server="$server_spec"
    export_path="${NFS_ROMS_PATH}"
  elif [[ -n "$server_spec" && "$server_spec" == *":/"* ]]; then
    printf -v server '%s' "${server_spec%%:*}"
    printf -v export_path '%s' "${server_spec#*:}"
  else
    server="$server_spec"
    export_path="$default_export_path"
  fi

  if [[ -z "$server" ]]; then
    cover_path "mount-nfs:missing-config"
    log "NFS config missing (set NFS_SERVER to either host or host:/export/path)"
    exit 2
  fi

  require_cmd mount
  require_cmd mountpoint

  run_cmd mkdir -p "$mount_point"

  if mountpoint -q "$mount_point"; then
    cover_path "mount-nfs:already-mounted"
    log "Already mounted at $mount_point"
    exit 0
  fi

  log "Mounting ${server}:${export_path} -> ${mount_point} (opts: ${mount_opts})"

  # Fail-open semantics: if NFS is unavailable, do not fail the appliance.
  cover_path "mount-nfs:mount-attempt"
  if ! run_cmd mount -t nfs -o "$mount_opts" "${server}:${export_path}" "$mount_point"; then
    cover_path "mount-nfs:mount-failed"
    log "Mount failed; continuing without NFS"
    exit 0
  fi

  cover_path "mount-nfs:mount-success"

  # Create required subfolders inside the share.
  # Backups are expected to be writable; ROMs may or may not exist.
  if ! run_cmd mkdir -p "$mount_point/backups"; then
    cover_path "mount-nfs:mkdir-failed"
    log "Mounted but unable to create required dirs (need rw share): $mount_point/backups"
    exit 0
  fi

  # Best-effort: do not fail if we cannot create roms/.
  run_cmd mkdir -p "$mount_point/roms" || true

  cover_path "mount-nfs:dirs-ready"
  log "Mounted successfully"
}

if ! kiosk_retropie_is_sourced; then
  main "$@"
fi
