#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
  setup_test_root
  export RETRO_HA_DRY_RUN=1
}

teardown() {
  teardown_test_root
}

@test "mount-nfs records not-configured path" {
  unset NFS_SERVER NFS_PATH
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs:not-configured"
}

@test "mount-nfs records already-mounted path" {
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNTPOINT_PATHS="$TEST_ROOT/mnt/retro-ha-roms\n"
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs:already-mounted"
}

@test "mount-nfs records mount-failed path (fail-open)" {
  export RETRO_HA_DRY_RUN=0
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNT_EXIT_CODE=32
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs:mount-attempt"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs:mount-failed"
}

@test "mount-nfs records mount-success path" {
  export RETRO_HA_DRY_RUN=0
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNT_EXIT_CODE=0
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs:mount-success"
}

@test "mount-nfs-backup disabled path" {
  export RETRO_HA_SAVE_BACKUP_ENABLED=0
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs-backup:disabled"
}

@test "mount-nfs-backup not-configured path" {
  export RETRO_HA_SAVE_BACKUP_ENABLED=1
  unset RETRO_HA_SAVE_BACKUP_NFS_SERVER RETRO_HA_SAVE_BACKUP_NFS_PATH NFS_SERVER NFS_PATH
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs-backup:not-configured"
}

@test "mount-nfs-backup already-mounted path" {
  export RETRO_HA_SAVE_BACKUP_ENABLED=1
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNTPOINT_PATHS="$TEST_ROOT/mnt/retro-ha-backup\n"
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs-backup:already-mounted"
}

@test "mount-nfs-backup mount-failed path (fail-open)" {
  export RETRO_HA_DRY_RUN=0
  export RETRO_HA_SAVE_BACKUP_ENABLED=1
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNT_EXIT_CODE=32
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs-backup:mount-attempt"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs-backup:mount-failed"
}

@test "mount-nfs-backup mount-success path" {
  export RETRO_HA_DRY_RUN=0
  export RETRO_HA_SAVE_BACKUP_ENABLED=1
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNT_EXIT_CODE=0
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/mount-nfs-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH mount-nfs-backup:mount-success"
}

@test "sync-roms skips when rsync missing" {
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNTPOINT_PATHS="$TEST_ROOT/mnt/retro-ha-roms\n"
  make_isolated_path_with_stubs dirname mountpoint mount
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/sync-roms.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:rsync-missing"
}

@test "sync-roms skips when not mounted" {
  export NFS_SERVER=server
  export NFS_PATH=/export
  unset MOUNTPOINT_PATHS
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/sync-roms.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:not-mounted"
}

@test "sync-roms with allowlist + exclude + delete" {
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNTPOINT_PATHS="$TEST_ROOT/mnt/retro-ha-roms\n"

  # Fake NFS tree under RETRO_HA_ROOT.
  mkdir -p "$TEST_ROOT/mnt/retro-ha-roms/nes" "$TEST_ROOT/mnt/retro-ha-roms/snes"
  export RETRO_HA_ROMS_SYSTEMS="nes,snes"
  export RETRO_HA_ROMS_EXCLUDE_SYSTEMS="snes"
  export RETRO_HA_ROMS_SYNC_DELETE=1

  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/sync-roms.sh"
  assert_success

  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:delete-enabled"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:allowlist"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:excluded"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:chown"
}

@test "sync-roms records with-subdir + src-missing" {
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNTPOINT_PATHS="$TEST_ROOT/mnt/retro-ha-roms\n"
  export RETRO_HA_NFS_ROMS_SUBDIR=subdir
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/sync-roms.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:with-subdir"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:src-missing"
}

@test "sync-roms records discover + missing-system" {
  export NFS_SERVER=server
  export NFS_PATH=/export
  export MOUNTPOINT_PATHS="$TEST_ROOT/mnt/retro-ha-roms\n"

  mkdir -p "$TEST_ROOT/mnt/retro-ha-roms/nes"
  export RETRO_HA_ROMS_SYSTEMS="nes,snes"

  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/sync-roms.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:allowlist"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:missing-system"

  # Now switch to discovery mode.
  unset RETRO_HA_ROMS_SYSTEMS
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/sync-roms.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH sync-roms:discover"
}

@test "save-backup records rsync-missing when mounted but rsync absent" {
  export RETRO_HA_SAVE_BACKUP_ENABLED=1
  # systemctl stub uses 0 for active; set to 1 = inactive (not in Retro mode).
  export SYSTEMCTL_ACTIVE_RETRO=1

  # Mark backup as mounted.
  export MOUNTPOINT_PATHS="$TEST_ROOT/mnt/retro-ha-backup\n"

  # Remove rsync from PATH by isolating it.
  make_isolated_path_with_stubs dirname mountpoint systemctl

  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/save-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH save-backup:rsync-missing"
}

@test "save-backup backup-saves and backup-states with delete" {
  export RETRO_HA_SAVE_BACKUP_ENABLED=1
  # Not in Retro mode.
  export SYSTEMCTL_ACTIVE_RETRO=1

  # Backup mounted.
  export MOUNTPOINT_PATHS="$TEST_ROOT/mnt/retro-ha-backup\n"

  mkdir -p "$TEST_ROOT/var/lib/retro-ha/retropie/saves" "$TEST_ROOT/var/lib/retro-ha/retropie/states"
  export RETRO_HA_SAVE_BACKUP_DELETE=1

  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/save-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH save-backup:delete-enabled"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH save-backup:backup-saves"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH save-backup:backup-states"
}

@test "save-backup records disabled/retro-active/not-mounted paths" {
  export RETRO_HA_SAVE_BACKUP_ENABLED=0
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/save-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH save-backup:disabled"

  export RETRO_HA_SAVE_BACKUP_ENABLED=1
  export SYSTEMCTL_ACTIVE_RETRO=0
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/save-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH save-backup:retro-active"

  export SYSTEMCTL_ACTIVE_RETRO=1
  unset MOUNTPOINT_PATHS
  run bash "$RETRO_HA_REPO_ROOT/scripts/nfs/save-backup.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH save-backup:not-mounted"
}
