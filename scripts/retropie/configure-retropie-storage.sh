#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "retropie-storage [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

require_root() {
  if [[ "${KIOSK_RETROPIE_ALLOW_NON_ROOT:-0}" == "1" ]]; then
    return 0
  fi
  local effective_uid="${KIOSK_RETROPIE_EUID_OVERRIDE:-${EUID:-$(id -u)}}"
  if [[ "$effective_uid" -ne 0 ]]; then
    die "Must run as root"
  fi
}

ensure_kv_line() {
  local file="$1"
  local key="$2"
  local value="$3"

  run_cmd mkdir -p "$(dirname "$file")"
  run_cmd touch "$file"

  # Portable edit (macOS sed -i differs).
  local tmp
  tmp="$(mktemp)"
  if grep -Eq "^${key}[[:space:]]*=" "$file"; then
    awk -v k="$key" -v v="$value" 'BEGIN{replaced=0} $0 ~ "^" k "[[:space:]]*=" {print k " = \"" v "\""; replaced=1; next} {print} END{if (replaced==0) print k " = \"" v "\""}' "$file" > "$tmp"
  else
    cat "$file" > "$tmp"
    echo "${key} = \"${value}\"" >> "$tmp"
  fi
  if [[ "${KIOSK_RETROPIE_DRY_RUN:-0}" == "1" ]]; then
    cover_path "retropie-storage:dry-run"
    record_call "write_kv ${file} ${key}"
    run_cmd rm -f "$tmp"
    return 0
  fi
  mv "$tmp" "$file"
}

main() {
  export KIOSK_RETROPIE_LOG_PREFIX="retropie-storage"

  require_root

  local user="retropi"
  local home_dir
  home_dir="$(getent passwd "$user" | cut -d: -f6 || true)"
  [[ -n "$home_dir" ]] || die "Unable to resolve home directory for $user"

  local roms_dir
  roms_dir="$(kiosk_retropie_path /var/lib/kiosk-retropie/retropie/roms)"
  local saves_dir
  saves_dir="$(kiosk_retropie_path /var/lib/kiosk-retropie/retropie/saves)"
  local states_dir
  states_dir="$(kiosk_retropie_path /var/lib/kiosk-retropie/retropie/states)"

  run_cmd mkdir -p "$roms_dir" "$saves_dir" "$states_dir"
  run_cmd chown -R "$user:$user" "$(kiosk_retropie_path /var/lib/kiosk-retropie/retropie)" || true

  # Back-compat: keep the old default path working if anything references it.
  if [[ ! -e "$(kiosk_retropie_path /var/lib/kiosk-retropie/roms)" ]]; then
    run_cmd ln -s "$roms_dir" "$(kiosk_retropie_path /var/lib/kiosk-retropie/roms)"
  fi

  # Point RetroPie ROMs directory at our local ROM store.
  local retropie_dir="$home_dir/RetroPie"
  run_cmd mkdir -p "$retropie_dir"
  run_cmd chown "$user:$user" "$retropie_dir"

  local target="$retropie_dir/roms"
  if [[ -L "$target" ]]; then
    :
  elif [[ -e "$target" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    run_cmd mv "$target" "${target}.bak-${ts}"
  fi
  run_cmd ln -snf "$roms_dir" "$target"
  run_cmd chown -h "$user:$user" "$target" || true

  # Configure RetroArch save/state paths if RetroPie is installed.
  local retroarch_cfg
  retroarch_cfg="$(kiosk_retropie_path /opt/retropie/configs/all/retroarch.cfg)"
  if [[ -f "$retroarch_cfg" ]]; then
    cover_path "retropie-storage:retroarch-present"
    log "Configuring RetroArch save/state dirs"
    ensure_kv_line "$retroarch_cfg" "savefile_directory" "$saves_dir"
    ensure_kv_line "$retroarch_cfg" "savestate_directory" "$states_dir"
  else
    cover_path "retropie-storage:retroarch-missing"
    log "RetroArch config not found at $retroarch_cfg (RetroPie not installed yet); skipping"
  fi

  log "Storage configured (ROMs=$roms_dir saves=$saves_dir states=$states_dir)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
