#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  # Provide cover_path for branch/path coverage markers in the library.
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/common.sh"
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/list.sh"
}

@test "split_list splits comma and whitespace" {
  run split_list "a,b c  d"
  assert_success
  assert_output $'a\nb\nc\nd'
}

@test "split_list on empty input yields no output" {
  run split_list ""
  assert_success
  assert_output ""
}

@test "in_list returns success when present" {
  run in_list "b" "a" "b" "c"
  assert_success
}

@test "in_list returns failure when absent" {
  run in_list "x" "a" "b" "c"
  assert_failure
}
