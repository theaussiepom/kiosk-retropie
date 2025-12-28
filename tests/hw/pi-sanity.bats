#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"

@test "Host sanity: running on Linux" {
  run uname -s
  assert_success
  assert_equal "$output" "Linux"
}

@test "Host sanity: ARM64 runner" {
  run uname -m
  assert_success
  # Common values: aarch64 (Linux), arm64 (some distros).
  # This suite is intended for the Pi runner; skip when run on non-ARM64 dev machines.
  if [[ ! "$output" =~ ^(aarch64|arm64)$ ]]; then
    skip "Not an ARM64 host (uname -m=$output)"
  fi
}

@test "Raspberry Pi model file is readable (when present)" {
  if [[ ! -f /proc/device-tree/model ]]; then
    skip "/proc/device-tree/model not present (non-RPi ARM64 host?)"
  fi

  run cat /proc/device-tree/model
  assert_success

  # Allow trailing NULs.
  assert_output --partial "Raspberry Pi"
}

@test "vcgencmd works (when present)" {
  if ! command -v vcgencmd >/dev/null 2>&1; then
    skip "vcgencmd not installed"
  fi

  run vcgencmd get_throttled
  assert_success
  assert_regex "$output" '^throttled=0x[0-9a-fA-F]+$'
}
