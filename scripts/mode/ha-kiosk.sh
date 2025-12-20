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
  echo "ha-kiosk [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

chromium_bin() {
  if command -v chromium-browser > /dev/null 2>&1; then
    echo chromium-browser
    return 0
  fi
  if command -v chromium > /dev/null 2>&1; then
    echo chromium
    return 0
  fi
  return 1
}

main() {
  export RETRO_HA_LOG_PREFIX="ha-kiosk"

  if [[ -z "${HA_URL:-}" ]]; then
    cover_path "ha-kiosk:missing-ha-url"
    die "HA_URL is required (set to your dashboard URL in /etc/retro-ha/config.env)"
  fi

  local x_display=":0"
  local vt="${RETRO_HA_X_VT:-7}"

  local runtime_dir="${XDG_RUNTIME_DIR:-$(retro_ha_path "/run/user/$(id -u)")}"
  local state_dir="${runtime_dir}/retro-ha"
  run_cmd mkdir -p "$state_dir"

  local xinitrc="${state_dir}/ha-xinitrc"

  local chromium
  if ! chromium="$(chromium_bin)"; then
    cover_path "ha-kiosk:missing-chromium"
    die "Chromium not found (expected chromium or chromium-browser)"
  fi

  if [[ "$chromium" == "chromium-browser" ]]; then
    cover_path "ha-kiosk:chromium-browser"
  fi

  # Dedicated kiosk profile.
  local profile_dir="${RETRO_HA_CHROMIUM_PROFILE_DIR:-$HOME/.config/retro-ha-chromium}"
  run_cmd mkdir -p "$profile_dir"

  if [[ "${RETRO_HA_DRY_RUN:-0}" == "1" ]]; then
    record_call "write_file $xinitrc"
  else
    cat > "$xinitrc" << EOF
#!/usr/bin/env bash
set -euo pipefail

# Keep display awake.
if command -v xset >/dev/null 2>&1; then
  xset s off
  xset -dpms
  xset s noblank
fi

# Optional rotation (xrandr names: normal,left,right,inverted).
if [[ -n "${RETRO_HA_SCREEN_ROTATION:-}" ]] && command -v xrandr >/dev/null 2>&1; then
  xrandr -o "${RETRO_HA_SCREEN_ROTATION:-}" || true
fi

exec "$chromium" \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=TranslateUI \
  --autoplay-policy=no-user-gesture-required \
  --user-data-dir="$profile_dir" \
  "$HA_URL"
EOF
  fi

  run_cmd chmod 0755 "$xinitrc"

  # Ensure we don't inherit a stale X lock/socket.
  run_cmd rm -f "$(retro_ha_path "/tmp/.X${x_display#:}-lock")" "$(retro_ha_path "/tmp/.X11-unix/X${x_display#:}")" || true

  log "Starting Xorg on vt${vt}, display ${x_display}"

  # xinit syntax:
  #   xinit <client> -- <server> <display> [server-args...]
  if [[ "${RETRO_HA_DRY_RUN:-0}" == "1" ]]; then
    cover_path "ha-kiosk:dry-run"
    record_call "exec xinit $xinitrc -- /usr/lib/xorg/Xorg $x_display vt${vt} -nolisten tcp -keeptty"
    exit 0
  fi

  exec xinit "$xinitrc" -- /usr/lib/xorg/Xorg "$x_display" "vt${vt}" -nolisten tcp -keeptty
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
