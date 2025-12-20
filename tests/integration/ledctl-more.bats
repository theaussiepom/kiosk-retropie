#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
  setup_test_root

  # Fake LED sysfs under RETRO_HA_ROOT.
  mkdir -p "$TEST_ROOT/sys/class/leds/led0" "$TEST_ROOT/sys/class/leds/led1"
  echo "none [mmc0] timer" > "$TEST_ROOT/sys/class/leds/led0/trigger"
  echo "none default-on" > "$TEST_ROOT/sys/class/leds/led1/trigger"
  echo 0 > "$TEST_ROOT/sys/class/leds/led0/brightness"
  echo 0 > "$TEST_ROOT/sys/class/leds/led1/brightness"
}

teardown() {
  teardown_test_root
}

@test "ledctl usage when argc wrong" {
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh"
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:usage-argc"
}

@test "ledctl invalid target" {
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" nope on
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:invalid-target"
}

@test "ledctl invalid state" {
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" act nope
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:invalid-state"
}

@test "ledctl act on supported trigger path" {
  export RETRO_HA_ACT_LED_TRIGGER_ON=mmc0
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" act on
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:act-on-supported"
}

@test "ledctl act on unsupported trigger path" {
  export RETRO_HA_ACT_LED_TRIGGER_ON=not-a-trigger
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" act on
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:act-on-unsupported"
}

@test "ledctl act off path" {
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" act off
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:act-off"
}

@test "ledctl pwr on supported trigger path" {
  # Default trigger file includes 'default-on'
  export RETRO_HA_PWR_LED_TRIGGER_ON=default-on
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" pwr on
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:pwr-on-supported"
}

@test "ledctl pwr on unsupported trigger path" {
  export RETRO_HA_PWR_LED_TRIGGER_ON=not-a-trigger
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" pwr on
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:pwr-on-unsupported"
}

@test "ledctl pwr off path" {
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" pwr off
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH ledctl:pwr-off"
}

@test "leds-on wrapper runs" {
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/leds-on.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH leds-on:run"
}

@test "leds-off wrapper runs" {
  run bash "$RETRO_HA_REPO_ROOT/scripts/leds/leds-off.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH leds-off:run"
}
