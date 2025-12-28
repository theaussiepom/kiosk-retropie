#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"

is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

have_passwordless_sudo() {
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true >/dev/null 2>&1
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

pick_backlight_dir() {
  local d
  for d in /sys/class/backlight/*; do
    [[ -d "$d" ]] || continue
    echo "$d"
    return 0
  done
  return 1
}

setup() {
  if ! is_linux; then
    skip "Linux-only backlight tests"
  fi

  BACKLIGHT_DIR="$(pick_backlight_dir || true)"
  if [[ -z "$BACKLIGHT_DIR" ]]; then
    skip "No /sys/class/backlight device present"
  fi

  BRIGHTNESS_FILE="$BACKLIGHT_DIR/brightness"
  MAX_BRIGHTNESS_FILE="$BACKLIGHT_DIR/max_brightness"

  if [[ ! -f "$BRIGHTNESS_FILE" || ! -f "$MAX_BRIGHTNESS_FILE" ]]; then
    skip "Backlight sysfs missing brightness/max_brightness"
  fi

  ORIG_BRIGHTNESS="$(cat "$BRIGHTNESS_FILE")"
  MAX_BRIGHTNESS="$(cat "$MAX_BRIGHTNESS_FILE")"

  export BACKLIGHT_DIR BRIGHTNESS_FILE MAX_BRIGHTNESS_FILE ORIG_BRIGHTNESS MAX_BRIGHTNESS
}

teardown() {
  # Best-effort restore.
  if [[ -n "${ORIG_BRIGHTNESS:-}" ]]; then
    write_sysfs "$BRIGHTNESS_FILE" "$ORIG_BRIGHTNESS" >/dev/null 2>&1 || true
  fi
}

@test "Backlight sysfs device is present" {
  assert [ -d "$BACKLIGHT_DIR" ]
  assert [ -f "$BRIGHTNESS_FILE" ]
  assert [ -f "$MAX_BRIGHTNESS_FILE" ]
}

@test "Backlight brightness can be changed and restored" {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]] && ! have_passwordless_sudo; then
    skip "Need root or passwordless sudo to write backlight brightness"
  fi

  # Choose a non-destructive target: half of max (or 0 if max is 0).
  local target
  if [[ "$MAX_BRIGHTNESS" =~ ^[0-9]+$ ]] && (( MAX_BRIGHTNESS > 0 )); then
    target=$((MAX_BRIGHTNESS / 2))
  else
    target=0
  fi

  run write_sysfs "$BRIGHTNESS_FILE" "$target"
  assert_success

  run cat "$BRIGHTNESS_FILE"
  assert_success
  assert_equal "$output" "$target"
}
