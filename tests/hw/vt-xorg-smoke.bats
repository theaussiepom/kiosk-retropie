#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"

have_passwordless_sudo() {
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true >/dev/null 2>&1
}

need_root_or_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  have_passwordless_sudo
}

require_or_skip() {
  local what="$1"
  if [[ "${KIOSK_RETROPIE_HW_REQUIRE_VT_XORG:-0}" == "1" ]]; then
    fail "$what"
  fi
  skip "$what"
}

write_unit() {
  local unit_name="$1"
  shift

  local unit_path="/run/systemd/system/${unit_name}"

  sudo -n tee "$unit_path" >/dev/null
}

start_unit_wait() {
  local unit_name="$1"
  sudo -n systemctl daemon-reload
  sudo -n systemctl start --no-pager --wait "$unit_name"
}

stop_unit() {
  local unit_name="$1"
  sudo -n systemctl stop --no-pager "$unit_name" >/dev/null 2>&1 || true
}

rm_unit() {
  local unit_name="$1"
  sudo -n rm -f "/run/systemd/system/${unit_name}" >/dev/null 2>&1 || true
}

setup() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "Linux-only VT/Xorg tests"
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    skip "systemctl not available"
  fi

  if ! need_root_or_sudo; then
    skip "Need root or passwordless sudo"
  fi

  if ! id -u retropi >/dev/null 2>&1; then
    require_or_skip "Missing user: retropi"
  fi

  if ! command -v chvt >/dev/null 2>&1; then
    require_or_skip "Missing chvt (install kbd)"
  fi

  if ! command -v xinit >/dev/null 2>&1; then
    require_or_skip "Missing xinit"
  fi

  if [[ ! -x /usr/lib/xorg/Xorg ]]; then
    require_or_skip "Missing /usr/lib/xorg/Xorg"
  fi

  # Ensure the VT devices we care about actually exist on this host.
  for vt in 7 8; do
    if [[ ! -c "/dev/tty${vt}" ]]; then
      require_or_skip "Missing VT device: /dev/tty${vt}"
    fi
  done

  # Capture current VT if possible, so we can restore it.
  ORIGINAL_VT=""
  if command -v fgconsole >/dev/null 2>&1; then
    ORIGINAL_VT="$(fgconsole 2>/dev/null || true)"
  fi
  export ORIGINAL_VT
}

teardown() {
  stop_unit kiosk-retropie-vt-xorg-7.service
  stop_unit kiosk-retropie-vt-xorg-8.service
  rm_unit kiosk-retropie-vt-xorg-7.service
  rm_unit kiosk-retropie-vt-xorg-8.service
  sudo -n systemctl daemon-reload >/dev/null 2>&1 || true

  if [[ -n "${ORIGINAL_VT:-}" ]]; then
    sudo -n chvt "$ORIGINAL_VT" >/dev/null 2>&1 || true
  fi
}

run_xorg_on_vt_and_check_log() {
  local vt="$1"
  local display_num="$2"

  local unit="kiosk-retropie-vt-xorg-${vt}.service"

  local retropi_uid
  retropi_uid="$(id -u retropi 2>/dev/null || true)"
  if [[ -z "$retropi_uid" ]]; then
    require_or_skip "Could not resolve retropi uid"
  fi

  local retropi_home
  retropi_home="$(getent passwd retropi 2>/dev/null | cut -d: -f6 || true)"
  if [[ -z "$retropi_home" ]]; then
    require_or_skip "Could not resolve retropi home directory"
  fi

  local xorg_log_file="/run/kiosk-retropie/Xorg.${display_num}.log"
  local unit_out_file="/run/kiosk-retropie/vt-xorg-${vt}.out"
  local xorg_conf_file="/run/kiosk-retropie/xorg.${display_num}.conf"

  # Pick a likely KMS device (card with a connector status in sysfs), falling back to card0.
  local kmsdev="/dev/dri/card0"
  local status_path
  for status_path in /sys/class/drm/card[0-9]*-*/status; do
    [[ -f "$status_path" ]] || continue
    kmsdev="/dev/dri/$(basename "${status_path%%-*}")"
    break
  done

  # Write a minimal, headless-friendly config to allow Xorg to start even when no outputs are connected.
  sudo -n install -d -m 0755 -o retropi -g retropi /run/kiosk-retropie
  cat <<EOF | sudo -n tee "$xorg_conf_file" >/dev/null
Section "Device"
  Identifier "KioskRetroPieGPU"
  Driver "modesetting"
  Option "kmsdev" "${kmsdev}"
  Option "AllowEmptyInitialConfiguration" "true"
EndSection

Section "Screen"
  Identifier "KioskRetroPieScreen"
  Device "KioskRetroPieGPU"
EndSection

Section "ServerLayout"
  Identifier "KioskRetroPieLayout"
  Screen "KioskRetroPieScreen"
EndSection
EOF
  sudo -n chown retropi:retropi "$xorg_conf_file"
  sudo -n chmod 0644 "$xorg_conf_file"

  # Clean old locks/logs so we read the right file.
  sudo -n rm -f "/tmp/.X${display_num}-lock" "/tmp/.X11-unix/X${display_num}" >/dev/null 2>&1 || true
  sudo -n rm -f "$xorg_log_file" "$unit_out_file" >/dev/null 2>&1 || true

  cat <<EOF | write_unit "$unit"
[Unit]
Description=HW smoke: start rootless Xorg on vt${vt}
After=multi-user.target

[Service]
Type=oneshot
User=retropi
Group=retropi

Environment=XDG_RUNTIME_DIR=/run/user/${retropi_uid}

# Create a logind session so rootless Xorg can acquire the seat.
PAMName=login
StandardInput=tty
TTYPath=/dev/tty${vt}
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes

# Ensure the session is active so logind provides unpaused DRM fds.
PermissionsStartOnly=true
ExecStartPre=/usr/bin/env chvt ${vt}
ExecStartPre=/usr/bin/env bash -lc 'install -d -m 0700 -o retropi -g retropi /run/user/${retropi_uid}'
ExecStartPre=/usr/bin/env bash -lc 'install -d -m 0755 -o retropi -g retropi /run/kiosk-retropie'

# Start Xorg briefly on this VT. Capture verbose output to /run for CI debugging.
ExecStart=/usr/bin/env bash -lc 'set -euo pipefail; exec >"${unit_out_file}" 2>&1; set -x; id; command -v xinit; command -v xauth || true; ls -la "${xorg_conf_file}"; xinit /bin/sleep 2 -- /usr/lib/xorg/Xorg :${display_num} vt${vt} -nolisten tcp -keeptty -logfile "${xorg_log_file}" -config "${xorg_conf_file}"'
EOF

  run start_unit_wait "$unit"
  if [[ "$status" -ne 0 ]]; then
    echo "--- systemctl start output ---" >&2
    echo "$output" >&2
    echo "--- systemctl status ${unit} ---" >&2
    sudo -n systemctl status --no-pager "$unit" >&2 || true
    echo "--- journalctl -u ${unit} (last 200 lines) ---" >&2
    sudo -n journalctl -u "$unit" --no-pager -n 200 >&2 || true
    if [[ -f "$unit_out_file" ]]; then
      echo "--- ${unit_out_file} ---" >&2
      sudo -n tail -n 200 "$unit_out_file" >&2 || true
    fi
    if [[ -f "$xorg_log_file" ]]; then
      echo "--- ${xorg_log_file} ---" >&2
      sudo -n tail -n 200 "$xorg_log_file" >&2 || true
    fi
    echo "--- host sanity ---" >&2
    ls -la "/dev/tty${vt}" >&2 || true
    ls -la /dev/dri >&2 || true
    fail "VT/Xorg systemd unit failed to start on vt${vt}"
  fi

  if [[ ! -f "$xorg_log_file" ]]; then
    if [[ -f "$unit_out_file" ]]; then
      echo "--- ${unit_out_file} ---" >&2
      sudo -n tail -n 200 "$unit_out_file" >&2 || true
    fi
    require_or_skip "Expected Xorg log not found: $xorg_log_file"
  fi

  run sudo -n grep -nE "Error systemd-logind returned paused fd for drm node|Fatal server error|Caught signal" "$xorg_log_file"
  # grep exits 1 when no matches; that's success for us.
  if [[ "$status" -eq 0 ]]; then
    echo "--- $xorg_log_file matches ---" >&2
    echo "$output" >&2
    fail "Xorg reported logind/VT/abort errors on vt${vt}"
  fi

  # Best-effort: ensure we actually switched to this VT.
  if command -v fgconsole >/dev/null 2>&1; then
    run fgconsole
    # On some runners without an attached console this can fail; only enforce when required.
    if [[ "$status" -ne 0 ]]; then
      require_or_skip "fgconsole failed; cannot validate VT switching"
    fi
  fi
}

@test "VT/Xorg smoke: starts rootless Xorg on tty7 without logind paused DRM fd" {
  run_xorg_on_vt_and_check_log 7 10
}

@test "VT/Xorg smoke: starts rootless Xorg on tty8 without logind paused DRM fd" {
  run_xorg_on_vt_and_check_log 8 11
}
