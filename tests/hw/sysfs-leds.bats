#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"

is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

require_sysfs_leds() {
  [[ -d /sys/class/leds/led-act ]] || return 1
  [[ -d /sys/class/leds/led-pwr ]] || return 1
  return 0
}

have_passwordless_sudo() {
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true >/dev/null 2>&1
}

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return $?
  fi

  if have_passwordless_sudo; then
    sudo -n "$@"
    return $?
  fi

  return 126
}

read_active_trigger() {
  local trigger_file="$1"
  # Example: "none [mmc0] timer ..."; extract the value inside brackets.
  sed -n 's/.*\[\([^]]\+\)\].*/\1/p' "$trigger_file" | head -n 1
}

write_sysfs() {
  local file="$1"
  local value="$2"

  if [[ -w "$file" ]]; then
    printf '%s' "$value" >"$file"
    return 0
  fi

  if have_passwordless_sudo; then
    printf '%s' "$value" | sudo -n tee "$file" >/dev/null
    return $?
  fi

  return 126
}

setup() {
  if ! is_linux; then
    skip "Linux-only sysfs tests"
  fi

  if ! require_sysfs_leds; then
    skip "Expected sysfs LEDs not present (/sys/class/leds/led-act + led-pwr)"
  fi

  # Capture original triggers so we can restore them.
  ACT_TRIGGER_FILE="/sys/class/leds/led-act/trigger"
  PWR_TRIGGER_FILE="/sys/class/leds/led-pwr/trigger"

  ACT_ORIG_TRIGGER="$(read_active_trigger "$ACT_TRIGGER_FILE" || true)"
  PWR_ORIG_TRIGGER="$(read_active_trigger "$PWR_TRIGGER_FILE" || true)"

  export ACT_TRIGGER_FILE PWR_TRIGGER_FILE ACT_ORIG_TRIGGER PWR_ORIG_TRIGGER
}

teardown() {
  # Best-effort restore. If we lack perms, don’t fail teardown.
  if [[ -n "${ACT_ORIG_TRIGGER:-}" ]]; then
    write_sysfs "$ACT_TRIGGER_FILE" "$ACT_ORIG_TRIGGER" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PWR_ORIG_TRIGGER:-}" ]]; then
    write_sysfs "$PWR_TRIGGER_FILE" "$PWR_ORIG_TRIGGER" >/dev/null 2>&1 || true
  fi
}

@test "LED sysfs exists for led-act and led-pwr" {
  assert [ -d /sys/class/leds/led-act ]
  assert [ -d /sys/class/leds/led-pwr ]
  assert [ -f /sys/class/leds/led-act/brightness ]
  assert [ -f /sys/class/leds/led-pwr/brightness ]
  assert [ -f /sys/class/leds/led-act/trigger ]
  assert [ -f /sys/class/leds/led-pwr/trigger ]
}

@test "ledctl can turn LEDs off/on on real sysfs" {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]] && ! have_passwordless_sudo; then
    skip "Need root or passwordless sudo to write /sys/class/leds/*"
  fi

  run as_root bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" all off
  assert_success

  # Off should force brightness=0.
  run cat /sys/class/leds/led-act/brightness
  assert_success
  assert_equal "$output" "0"

  run cat /sys/class/leds/led-pwr/brightness
  assert_success
  assert_equal "$output" "0"

  run as_root bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" all on
  assert_success
}
