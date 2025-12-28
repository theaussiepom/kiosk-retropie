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

  if [[ -n "$server_spec" && "$server_spec" == \[*\]:* ]]; then
    # Bracketed IPv6 host syntax: [fe80::1]:/export/path
    server="${server_spec%%\]*}"
    server="${server#[}"
    local export_part
    export_part="${server_spec#*]:}"
    if [[ -z "$server" || -z "$export_part" ]]; then
      cover_path "mount-nfs:invalid-server-spec"
      log "Invalid NFS_SERVER (expected [ipv6]:/export/path): $server_spec"
      exit 0
    fi
    if [[ "$export_part" == /* ]]; then
      export_path="$export_part"
    else
      export_path="/$export_part"
    fi
  elif [[ -n "$server_spec" && "$server_spec" == *":"* ]]; then
    # Unbracketed values containing multiple colons are ambiguous (likely IPv6 or a typo).
    # Require bracketed IPv6 syntax instead of silently falling back.
    if [[ "$server_spec" == *":"*":"* ]]; then
      cover_path "mount-nfs:invalid-server-spec"
      log "Invalid NFS_SERVER (ambiguous host:export; use [ipv6]:/export/path for IPv6): $server_spec"
      exit 0
    fi

    # Accept host:path forms without a leading slash (e.g. host:export/path).
    printf -v server '%s' "${server_spec%%:*}"
    local export_part
    printf -v export_part '%s' "${server_spec#*:}"

    if [[ -z "$server" || -z "$export_part" ]]; then
      cover_path "mount-nfs:invalid-server-spec"
      log "Invalid NFS_SERVER (expected host:/export/path): $server_spec"
      exit 0
    fi

    if [[ "$export_part" == /* ]]; then
      export_path="$export_part"
    else
      export_path="/$export_part"
    fi
  else
    server="$server_spec"
    export_path="$default_export_path"
  fi

  if [[ -z "$server" ]]; then
    cover_path "mount-nfs:disabled"
    log "NFS disabled (NFS_SERVER not set); skipping mount"
    exit 0
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
