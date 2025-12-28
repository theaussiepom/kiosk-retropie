#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
	# Allow running installer logic without root.
	export KIOSK_RETROPIE_ALLOW_NON_ROOT=1
	export KIOSK_RETROPIE_DRY_RUN=1
	write_config_env $'KIOSK_URL=https://example.invalid'
}

teardown() {
	teardown_test_root
}

@test "install.sh dry-run records expected high-level actions" {
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/install.sh"
	assert_success

	assert_file_contains "$TEST_ROOT/calls.log" "apt-get"
	assert_file_contains "$TEST_ROOT/calls.log" "install"
	assert_file_contains "$TEST_ROOT/calls.log" "systemctl"
	assert_file_contains "$TEST_ROOT/calls.log" "write_marker"
}

@test "install.sh dry-run covers configured Chromium profile dir path" {
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/install.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "PATH install:chromium-profile-fixed"
}

@test "install.sh fails when KIOSK_URL missing" {
	write_config_env $'NFS_SERVER=server'
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/install.sh"
	assert_failure
	assert_output --partial "KIOSK_URL is required"
	assert_file_contains "$TEST_ROOT/calls.log" "PATH install:missing-kiosk-url"
}

@test "install.sh succeeds when NFS_SERVER missing" {
	write_config_env $'KIOSK_URL=https://example.invalid'
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/install.sh"
	assert_success
}
