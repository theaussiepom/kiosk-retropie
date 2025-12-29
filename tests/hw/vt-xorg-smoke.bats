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
  local log_file="/home/retropi/.local/share/xorg/Xorg.${display_num}.log"

  # Clean old locks/logs so we read the right file.
  sudo -n rm -f "/tmp/.X${display_num}-lock" "/tmp/.X11-unix/X${display_num}" >/dev/null 2>&1 || true
  sudo -n rm -f "$log_file" "$log_file.old" >/dev/null 2>&1 || true

  cat <<EOF | write_unit "$unit"
[Unit]
Description=HW smoke: start rootless Xorg on vt${vt}
After=multi-user.target

[Service]
Type=oneshot
User=retropi
Group=retropi

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

# Start Xorg briefly on this VT. Client exits after a moment.
ExecStart=/usr/bin/env bash -lc 'xinit /bin/sleep 2 -- /usr/lib/xorg/Xorg :${display_num} vt${vt} -nolisten tcp -keeptty'
EOF

  run start_unit_wait "$unit"
  assert_success

  if [[ ! -f "$log_file" ]]; then
    require_or_skip "Expected Xorg log not found: $log_file"
  fi

  run sudo -n grep -nE "Error systemd-logind returned paused fd for drm node|Fatal server error|Caught signal" "$log_file"
  # grep exits 1 when no matches; that's success for us.
  if [[ "$status" -eq 0 ]]; then
    echo "--- $log_file matches ---" >&2
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
