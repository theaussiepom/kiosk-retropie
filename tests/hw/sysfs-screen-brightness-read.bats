#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"

setup() {
  # Source the real script (safe: main guard prevents execution on source).
  # This exercises path resolution + sysfs discovery against the real host.
  # shellcheck source=scripts/screen/screen-brightness-mqtt.sh
  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
}

@test "screen brightness script can read current backlight percent" {
  local dir
  dir="$(backlight_dir)"

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    skip "No /sys/class/backlight device present"
  fi

  run read_brightness_percent "$dir"
  assert_success

  # Must be an integer 0-100.
  assert_regex "$output" '^[0-9]+$'
  local p="$output"
  if ((p < 0 || p > 100)); then
    fail "Expected 0-100, got: $p"
  fi
}
