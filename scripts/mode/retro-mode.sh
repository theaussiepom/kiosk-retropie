#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "retro-mode [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=scripts/lib/x11.sh
source "$LIB_DIR/x11.sh"

main() {
  export KIOSK_RETROPIE_LOG_PREFIX="retro-mode"

  # This will be fully implemented once RetroPie is installed.
  # For now we try to launch EmulationStation if present.
  if ! command -v xinit > /dev/null 2>&1; then
    cover_path "retro-mode:missing-xinit"
    die "xinit not found"
  fi

  if ! command -v emulationstation > /dev/null 2>&1; then
    # During early bring-up RetroPie may not be installed yet. Don't thrash systemd.
    cover_path "retro-mode:missing-emulationstation"
    log "emulationstation not found (RetroPie not installed yet); exiting"
    exit 0
  fi

  local x_display=":0"
  local vt="${X_VT_RETROPIE:-${RETROPIE_X_VT:-${KIOSK_RETROPIE_RETRO_X_VT:-8}}}"

  log "Starting RetroPie (EmulationStation) on vt${vt}, display ${x_display}"

  local runtime_dir
  runtime_dir="$(kiosk_retropie_runtime_dir "$(id -u)")"
  local state_dir
  state_dir="$(kiosk_retropie_state_dir "$runtime_dir")"
  run_cmd mkdir -p "$state_dir"

  local xinitrc
  xinitrc="$(kiosk_retropie_xinitrc_path "$state_dir" "retro-xinitrc")"

  if [[ "${KIOSK_RETROPIE_DRY_RUN:-0}" == "1" ]]; then
    record_call "write_file $xinitrc"
  else
    kiosk_retropie_xinitrc_prelude > "$xinitrc"
    cat << 'EOF' >> "$xinitrc"

exec /usr/bin/emulationstation
EOF
  fi

  run_cmd chmod 0755 "$xinitrc"

  # Ensure we don't inherit a stale X lock/socket.
  local lock1 lock2
  IFS= read -r lock1 < <(kiosk_retropie_x_lock_paths "$x_display")
  IFS= read -r lock2 < <(kiosk_retropie_x_lock_paths "$x_display" | tail -n 1)
  run_cmd rm -f "$lock1" "$lock2" || true

  if [[ "${KIOSK_RETROPIE_DRY_RUN:-0}" == "1" ]]; then
    cover_path "retro-mode:dry-run"
    record_call "$(kiosk_retropie_xinit_exec_record "$xinitrc" "$x_display" "$vt")"
    exit 0
  fi

  exec xinit "$xinitrc" -- /usr/lib/xorg/Xorg "$x_display" "vt${vt}" -nolisten tcp -keeptty
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
