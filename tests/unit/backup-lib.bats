#!/usr/bin/env bats

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  export TEST_TMP
  TEST_TMP="$(mktemp -d)"

  # Provide cover_path for branch/path coverage markers in the library.
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/common.sh"
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/backup.sh"
}

test_teardown() {
  rm -rf "${TEST_TMP}" || true
}

@test "save_backup_rsync_args emits base args" {
  run save_backup_rsync_args 0
  assert_success
  assert_output $'-a\n--info=stats2\n--human-readable'
}

@test "save_backup_rsync_args includes --delete when enabled" {
  run save_backup_rsync_args 1
  assert_success
  assert_output $'-a\n--info=stats2\n--human-readable\n--delete'
}

@test "save_backup_plan emits nothing when no source dirs exist" {
  run save_backup_plan "$TEST_TMP/no-saves" "$TEST_TMP/no-states" "$TEST_TMP/bk" "sub"
  assert_success
  assert_output ""
}

@test "save_backup_plan emits saves only" {
  mkdir -p "$TEST_TMP/saves"

  run save_backup_plan "$TEST_TMP/saves" "$TEST_TMP/no-states" "$TEST_TMP/bk" "sub"
  assert_success
  assert_output $'saves\t'"$TEST_TMP/saves"$'\t'"$TEST_TMP/bk/sub/saves"
}

@test "save_backup_plan emits states only" {
  mkdir -p "$TEST_TMP/states"

  run save_backup_plan "$TEST_TMP/no-saves" "$TEST_TMP/states" "$TEST_TMP/bk" "sub"
  assert_success
  assert_output $'states\t'"$TEST_TMP/states"$'\t'"$TEST_TMP/bk/sub/states"
}

@test "save_backup_plan emits both when both exist" {
  mkdir -p "$TEST_TMP/saves" "$TEST_TMP/states"

  run save_backup_plan "$TEST_TMP/saves" "$TEST_TMP/states" "$TEST_TMP/bk" "sub"
  assert_success
  local expected
  expected="saves"$'\t'"$TEST_TMP/saves"$'\t'"$TEST_TMP/bk/sub/saves"$'\n'"states"$'\t'"$TEST_TMP/states"$'\t'"$TEST_TMP/bk/sub/states"
  assert_output "$expected"
}
