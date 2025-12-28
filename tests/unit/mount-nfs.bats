#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
	make_isolated_path_with_stubs dirname mount mountpoint
}

teardown() {
	teardown_test_root
}

@test "mount-nfs: skips when NFS_SERVER unset" {
	run env -u NFS_SERVER bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/nfs/mount-nfs.sh"
	assert_success

	# Should not attempt mount.
	if [[ -f "$KIOSK_RETROPIE_CALLS_FILE" ]]; then
		run grep -F "mount -t nfs" "$KIOSK_RETROPIE_CALLS_FILE"
		assert_failure
	fi
}

@test "mount-nfs: bare host uses default export path" {
	export NFS_SERVER="nas"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/nfs/mount-nfs.sh"
	assert_success

	assert_file_contains "$KIOSK_RETROPIE_CALLS_FILE" "mount -t nfs -o rw nas:/export/kiosk-retropie"
}

@test "mount-nfs: host:export/path (no leading slash) is accepted" {
	export NFS_SERVER="nas:export/kiosk-retropie"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/nfs/mount-nfs.sh"
	assert_success

	assert_file_contains "$KIOSK_RETROPIE_CALLS_FILE" "mount -t nfs -o rw nas:/export/kiosk-retropie"
}

@test "mount-nfs: host:/export/path is accepted" {
	export NFS_SERVER="nas:/export/kiosk-retropie"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/nfs/mount-nfs.sh"
	assert_success

	assert_file_contains "$KIOSK_RETROPIE_CALLS_FILE" "mount -t nfs -o rw nas:/export/kiosk-retropie"
}

@test "mount-nfs: host: (missing export) is treated as invalid and skipped" {
	export NFS_SERVER="nas:"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/nfs/mount-nfs.sh"
	assert_success

	run grep -F "mount -t nfs" "$KIOSK_RETROPIE_CALLS_FILE"
	assert_failure
}

@test "mount-nfs: unbracketed multi-colon value is treated as invalid and skipped" {
	export NFS_SERVER="fe80::1:/export/kiosk-retropie"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/nfs/mount-nfs.sh"
	assert_success

	run grep -F "mount -t nfs" "$KIOSK_RETROPIE_CALLS_FILE"
	assert_failure
}

@test "mount-nfs: bracketed IPv6 host syntax is accepted" {
	export NFS_SERVER="[fe80::1]:export/kiosk-retropie"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/nfs/mount-nfs.sh"
	assert_success

	assert_file_contains "$KIOSK_RETROPIE_CALLS_FILE" "mount -t nfs -o rw fe80::1:/export/kiosk-retropie"
}
