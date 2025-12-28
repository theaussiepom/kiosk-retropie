#!/usr/bin/env bash
set -euo pipefail

# X11 / xinit helpers shared by kiosk and retro-mode.

kiosk_retropie_runtime_dir() {
  # Prefer XDG_RUNTIME_DIR if set; otherwise, /run/user/<uid> under KIOSK_RETROPIE_ROOT.
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

  kiosk_retropie_path "/run/user/${uid}"
}

kiosk_retropie_state_dir() {
  local runtime_dir="$1"
  printf '%s\n' "${runtime_dir}/kiosk-retropie"
}

kiosk_retropie_xinitrc_path() {
  local state_dir="$1"
  local name="$2" # e.g. kiosk-xinitrc or retro-xinitrc
  printf '%s\n' "${state_dir}/${name}"
}

kiosk_retropie_x_lock_paths() {
  local x_display="$1" # e.g. :0

  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-x11:x-lock-paths"
  fi
  printf '%s\n' "$(kiosk_retropie_path "/tmp/.X${x_display#:}-lock")"
  printf '%s\n' "$(kiosk_retropie_path "/tmp/.X11-unix/X${x_display#:}")"
}

kiosk_retropie_xinit_exec_record() {
  local xinitrc="$1"
  local x_display="$2"
  local vt="$3"

  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-x11:xinit-exec-record"
  fi
  printf '%s\n' "exec xinit ${xinitrc} -- /usr/lib/xorg/Xorg ${x_display} vt${vt} -nolisten tcp -keeptty"
}

kiosk_retropie_xinitrc_prelude() {
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
rotation_file="/run/kiosk-retropie/screen_rotation"
if [[ -n "${KIOSK_RETROPIE_ROOT:-}" && "${KIOSK_RETROPIE_ROOT}" != "/" ]]; then
  rotation_file="${KIOSK_RETROPIE_ROOT%/}${rotation_file}"
fi

if [[ -f "$rotation_file" ]]; then
  rotation="$(tr -d '[:space:]' <"$rotation_file" 2>/dev/null || true)"
else
  rotation="${KIOSK_SCREEN_ROTATION:-${KIOSK_RETROPIE_SCREEN_ROTATION:-}}"
fi
if [[ -n "$rotation" ]] && command -v xrandr >/dev/null 2>&1; then
  xrandr -o "$rotation" || true
fi
EOF
}
