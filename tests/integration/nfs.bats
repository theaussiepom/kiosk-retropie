#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
}

teardown() {
	teardown_test_root
}

@test "mount-nfs is fail-open when NFS not configured" {
	run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs.sh"
	assert_success
}

@test "mount-nfs calls mount when not mounted" {
	export NFS_SERVER=nas
	export NFS_PATH=/export/roms
	mp="$TEST_ROOT/mnt/retro-ha-roms"
	mkdir -p "$mp"

	# Not mounted initially.
	export MOUNTPOINT_PATHS=$''
	export MOUNT_EXIT_CODE=0

	run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "mount -t nfs"
}

@test "sync-roms rsyncs only allowed systems" {
	# Pretend NFS is mounted.
	mp="$TEST_ROOT/mnt/retro-ha-roms"
	mkdir -p "$mp/nes" "$mp/snes"
	export MOUNTPOINT_PATHS="$mp"

	# Avoid mount attempt.
	export NFS_SERVER=
	export NFS_PATH=

	# Allowlist only nes.
	export RETRO_HA_ROMS_SYSTEMS="nes"
	export RETRO_HA_ROMS_EXCLUDE_SYSTEMS="snes"

	run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/sync-roms.sh"
	assert_success

	assert_file_contains "$TEST_ROOT/calls.log" "rsync"
	assert_file_contains "$TEST_ROOT/calls.log" "$mp/nes/"
	refute_file_contains "$TEST_ROOT/calls.log" "$mp/snes/"
}

# Helper to assert a file does NOT contain a substring.
refute_file_contains() {
	local file="$1"
	local needle="$2"
	if [[ ! -f "$file" ]]; then
		return 0
	fi
	! grep -Fq -- "$needle" "$file"
}
