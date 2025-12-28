#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
}

teardown() {
	teardown_test_root
}

@test "save-backup no-ops when disabled" {
	export NFS_SAVE_BACKUP_ENABLED=0
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/nfs/save-backup.sh"
	assert_success
}

@test "save-backup skips during retro mode" {
	export NFS_SAVE_BACKUP_ENABLED=1
	export SYSTEMCTL_ACTIVE_RETRO=0
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/nfs/save-backup.sh"
	assert_success
}
