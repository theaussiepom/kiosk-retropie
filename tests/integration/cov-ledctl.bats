#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root

	mkdir -p "$TEST_ROOT/sys/class/leds/led0" "$TEST_ROOT/sys/class/leds/led1"

	printf '%s\n' 'none [mmc0] timer heartbeat' >"$TEST_ROOT/sys/class/leds/led0/trigger"
	printf '%s\n' '0' >"$TEST_ROOT/sys/class/leds/led0/brightness"

	printf '%s\n' 'none [default-on] timer heartbeat' >"$TEST_ROOT/sys/class/leds/led1/trigger"
	printf '%s\n' '0' >"$TEST_ROOT/sys/class/leds/led1/brightness"
}

teardown() {
	teardown_test_root
}

@test "ledctl off writes trigger=none and brightness=0" {
	run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" act off
	assert_success

	run cat "$TEST_ROOT/sys/class/leds/led0/trigger"
	assert_success
	assert_output --partial "none"

	run cat "$TEST_ROOT/sys/class/leds/led0/brightness"
	assert_success
	assert_output "0"
}

@test "ledctl on sets brightness=1 and restores supported trigger" {
	run bash "$RETRO_HA_REPO_ROOT/scripts/leds/ledctl.sh" act on
	assert_success

	run cat "$TEST_ROOT/sys/class/leds/led0/brightness"
	assert_success
	assert_output "1"

	run cat "$TEST_ROOT/sys/class/leds/led0/trigger"
	assert_success
	assert_output "mmc0"
}
