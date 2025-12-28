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
  echo "kiosk [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=scripts/lib/x11.sh
source "$LIB_DIR/x11.sh"

chromium_bin() {
  local candidate=""
  local c
  for c in chromium-browser chromium; do
    if command -v "$c" > /dev/null 2>&1; then
      candidate="$c"
      break
    fi
  done
  if [[ -z "$candidate" ]]; then
    return 1
  fi
  printf '%s\n' "$candidate"
  return 0
}

main() {
  export KIOSK_RETROPIE_LOG_PREFIX="kiosk"

  if [[ -z "${KIOSK_URL:-}" ]]; then
    cover_path "kiosk:missing-kiosk-url"
    die "KIOSK_URL is required (set to your kiosk URL in /etc/kiosk-retropie/config.env)"
  fi

  local x_display=":0"
  local vt="${X_VT_KIOSK:-${KIOSK_X_VT:-${KIOSK_RETROPIE_X_VT:-7}}}"

  local runtime_dir
  runtime_dir="$(kiosk_retropie_runtime_dir "$(id -u)")"
  local state_dir
  state_dir="$(kiosk_retropie_state_dir "$runtime_dir")"
  run_cmd mkdir -p "$state_dir"

  local xinitrc
  xinitrc="$(kiosk_retropie_xinitrc_path "$state_dir" "kiosk-xinitrc")"

  local chromium
  if ! chromium="$(chromium_bin)"; then
    cover_path "kiosk:missing-chromium"
    die "Chromium not found (expected chromium or chromium-browser)"
  fi

  if [[ "$chromium" == "chromium-browser" ]]; then
    cover_path "kiosk:chromium-browser"
  fi

  # Dedicated kiosk profile.
  local profile_dir="${KIOSK_CHROMIUM_PROFILE_DIR:-${KIOSK_RETROPIE_CHROMIUM_PROFILE_DIR:-$HOME/.config/kiosk-retropie-chromium}}"
  run_cmd mkdir -p "$profile_dir"

  if [[ "${KIOSK_RETROPIE_DRY_RUN:-0}" == "1" ]]; then
    record_call "write_file $xinitrc"
  else
    kiosk_retropie_xinitrc_prelude > "$xinitrc"
    cat << EOF >> "$xinitrc"

exec "$chromium" \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=TranslateUI \
  --autoplay-policy=no-user-gesture-required \
  --user-data-dir="$profile_dir" \
  "$KIOSK_URL"
EOF
  fi

  run_cmd chmod 0755 "$xinitrc"

  # Ensure we don't inherit a stale X lock/socket.
  local lock1 lock2
  IFS= read -r lock1 < <(kiosk_retropie_x_lock_paths "$x_display")
  IFS= read -r lock2 < <(kiosk_retropie_x_lock_paths "$x_display" | tail -n 1)
  run_cmd rm -f "$lock1" "$lock2" || true

  log "Starting Xorg on vt${vt}, display ${x_display}"

  # xinit syntax:
  #   xinit <client> -- <server> <display> [server-args...]
  if [[ "${KIOSK_RETROPIE_DRY_RUN:-0}" == "1" ]]; then
    cover_path "kiosk:dry-run"
    record_call "$(kiosk_retropie_xinit_exec_record "$xinitrc" "$x_display" "$vt")"
    exit 0
  fi

  exec xinit "$xinitrc" -- /usr/lib/xorg/Xorg "$x_display" "vt${vt}" -nolisten tcp -keeptty
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
