#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root

	mkdir -p "$TEST_ROOT/sys/class/leds/ledact" "$TEST_ROOT/sys/class/leds/ledpwr"

	printf '%s\n' 'none [mmc0] timer heartbeat' >"$TEST_ROOT/sys/class/leds/ledact/trigger"
	printf '%s\n' '0' >"$TEST_ROOT/sys/class/leds/ledact/brightness"

	printf '%s\n' 'none [default-on] timer heartbeat' >"$TEST_ROOT/sys/class/leds/ledpwr/trigger"
	printf '%s\n' '0' >"$TEST_ROOT/sys/class/leds/ledpwr/brightness"
}

teardown() {
	teardown_test_root
}

@test "ledctl off writes trigger=none and brightness=0" {
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" act off
	assert_success

	run cat "$TEST_ROOT/sys/class/leds/ledact/trigger"
	assert_success
	assert_output --partial "none"

	run cat "$TEST_ROOT/sys/class/leds/ledact/brightness"
	assert_success
	assert_output "0"
}

@test "ledctl on sets brightness=1 and restores supported trigger" {
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh" act on
	assert_success

	run cat "$TEST_ROOT/sys/class/leds/ledact/brightness"
	assert_success
	assert_output "1"

	run cat "$TEST_ROOT/sys/class/leds/ledact/trigger"
	assert_success
	assert_output "mmc0"
}
