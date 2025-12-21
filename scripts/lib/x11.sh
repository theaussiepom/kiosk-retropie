#!/usr/bin/env bash
set -euo pipefail

# X11 / xinit helpers shared by ha-kiosk and retro-mode.

retro_ha_runtime_dir() {
  # Prefer XDG_RUNTIME_DIR if set; otherwise, /run/user/<uid> under RETRO_HA_ROOT.
  local uid="${1:-}"
  if [[ -z "$uid" ]]; then
    uid="$(id -u)"
  fi

  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-x11:runtime-xdg"
    fi
    printf '%s\n' "$XDG_RUNTIME_DIR"
    return 0
  fi

  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-x11:runtime-fallback"
  fi

  retro_ha_path "/run/user/${uid}"
}

retro_ha_state_dir() {
  local runtime_dir="$1"
  printf '%s\n' "${runtime_dir}/retro-ha"
}

retro_ha_xinitrc_path() {
  local state_dir="$1"
  local name="$2" # e.g. ha-xinitrc or retro-xinitrc
  printf '%s\n' "${state_dir}/${name}"
}

retro_ha_x_lock_paths() {
  local x_display="$1" # e.g. :0

  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-x11:x-lock-paths"
  fi
  printf '%s\n' "$(retro_ha_path "/tmp/.X${x_display#:}-lock")"
  printf '%s\n' "$(retro_ha_path "/tmp/.X11-unix/X${x_display#:}")"
}

retro_ha_xinit_exec_record() {
  local xinitrc="$1"
  local x_display="$2"
  local vt="$3"

  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-x11:xinit-exec-record"
  fi
  printf '%s\n' "exec xinit ${xinitrc} -- /usr/lib/xorg/Xorg ${x_display} vt${vt} -nolisten tcp -keeptty"
}

retro_ha_xinitrc_prelude() {
  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-x11:xinitrc-prelude"
  fi
  cat << 'EOF'
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
EOF
}
