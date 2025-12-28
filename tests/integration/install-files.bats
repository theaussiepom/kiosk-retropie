#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
	export KIOSK_RETROPIE_ALLOW_NON_ROOT=1
	export KIOSK_RETROPIE_DRY_RUN=1
	write_config_env $'KIOSK_URL=https://example.invalid\nNFS_SERVER=server\nNFS_PATH=/export/kiosk-retropie'
}

teardown() {
	teardown_test_root
}

@test "install.sh dry-run installs shared libs" {
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/install.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "scripts/lib/common.sh"
	assert_file_contains "$TEST_ROOT/calls.log" "lib/common.sh"
	assert_file_contains "$TEST_ROOT/calls.log" "scripts/lib/logging.sh"
	assert_file_contains "$TEST_ROOT/calls.log" "lib/logging.sh"
	assert_file_contains "$TEST_ROOT/calls.log" "scripts/lib/path.sh"
	assert_file_contains "$TEST_ROOT/calls.log" "lib/path.sh"
	assert_file_contains "$TEST_ROOT/calls.log" "scripts/lib/x11.sh"
	assert_file_contains "$TEST_ROOT/calls.log" "lib/x11.sh"
	assert_file_contains "$TEST_ROOT/calls.log" "scripts/lib/backup.sh"
	assert_file_contains "$TEST_ROOT/calls.log" "lib/backup.sh"
}
