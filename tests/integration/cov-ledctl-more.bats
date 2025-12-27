#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
  setup_test_root

  # Fake LED sysfs under KIOSK_RETROPIE_ROOT.
  mkdir -p "$TEST_ROOT/sys/class/leds/ledact" "$TEST_ROOT/sys/class/leds/ledpwr"
  echo "none [mmc0] timer" > "$TEST_ROOT/sys/class/leds/ledact/trigger"
  echo "none default-on" > "$TEST_ROOT/sys/class/leds/ledpwr/trigger"
  echo 0 > "$TEST_ROOT/sys/class/leds/ledact/brightness"
  echo 0 > "$TEST_ROOT/sys/class/leds/ledpwr/brightness"
}

teardown() {
  teardown_test_root
}

@test "ledctl usage when argc wrong" {
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh"
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:usage-argc"
}

@test "ledctl invalid target" {
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" nope on
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:invalid-target"
}

@test "ledctl invalid state" {
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" act nope
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:invalid-state"
}

@test "ledctl act on supported trigger path" {
  export KIOSK_ACT_LED_TRIGGER_ON=mmc0
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" act on
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:act-on-supported"
}

@test "ledctl act on unsupported trigger path" {
  export KIOSK_ACT_LED_TRIGGER_ON=not-a-trigger
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" act on
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:act-on-unsupported"
}

@test "ledctl act off path" {
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" act off
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:act-off"
}

@test "ledctl pwr on supported trigger path" {
  # Default trigger file includes 'default-on'
  export KIOSK_PWR_LED_TRIGGER_ON=default-on
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" pwr on
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:pwr-on-supported"
}

@test "ledctl pwr on unsupported trigger path" {
  export KIOSK_PWR_LED_TRIGGER_ON=not-a-trigger
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" pwr on
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:pwr-on-unsupported"
}

@test "ledctl pwr off path" {
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" pwr off
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:pwr-off"
}

@test "leds-on wrapper runs" {
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/leds-on.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH leds-on:run"
}

@test "leds-off wrapper runs" {
  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/leds-off.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH leds-off:run"
}
