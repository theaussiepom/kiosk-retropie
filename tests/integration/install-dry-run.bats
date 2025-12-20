#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
	# Allow running installer logic without root.
	export RETRO_HA_ALLOW_NON_ROOT=1
	export RETRO_HA_DRY_RUN=1
}

teardown() {
	teardown_test_root
}

@test "install.sh dry-run records expected high-level actions" {
	run bash "$RETRO_HA_REPO_ROOT/scripts/install.sh"
	assert_success

	assert_file_contains "$TEST_ROOT/calls.log" "apt-get"
	assert_file_contains "$TEST_ROOT/calls.log" "install"
	assert_file_contains "$TEST_ROOT/calls.log" "systemctl"
	assert_file_contains "$TEST_ROOT/calls.log" "write_marker"
}
