#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"

have_passwordless_sudo() {
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true >/dev/null 2>&1
}

pick_evdev_device() {
  local p
  shopt -s nullglob
  for p in /dev/input/by-id/*event-joystick; do
    echo "$p"
    shopt -u nullglob
    return 0
  done
  shopt -u nullglob
  return 1
}

@test "controller listener (TTY) can open a real evdev device" {
  local dev
  dev="$(pick_evdev_device || true)"
  if [[ -z "$dev" ]]; then
    skip "No /dev/input/by-id/*event-joystick devices present"
  fi

  # Needs permissions to open /dev/input; on the Pi runner we run hw tests via sudo.
  if [[ "${EUID:-$(id -u)}" -ne 0 ]] && ! have_passwordless_sudo; then
    skip "Need root or passwordless sudo to open evdev devices"
  fi

  # Don’t emit any events; we just want to ensure the script can open and start listening.
  # Use max_loops=1 so it exits quickly (~1s) without triggering systemctl actions.
  run bash -lc "RETROPIE_INPUT_DEVICES='$dev' RETROPIE_MAX_LOOPS=1 RETROPIE_MAX_TRIGGERS=0 RETROPIE_ACTION_DEBOUNCE_SEC=0 bash '$KIOSK_RETROPIE_REPO_ROOT/scripts/input/controller-listener-tty.sh'"
  assert_success
  assert_output --partial "Listening on $dev"
}
