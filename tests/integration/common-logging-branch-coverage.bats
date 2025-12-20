#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
  setup_test_root
}

test_teardown() {
  teardown_test_root
}

@test "branch coverage: common.sh + logging.sh helper branches" {
  # common.sh branches
  source "$RETRO_HA_REPO_ROOT/scripts/lib/common.sh"

  # retro_ha_is_sourced branches: mirror the unit test pattern.
  local script
  script="$TEST_ROOT/sourced-check.sh"
  cat >"$script" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

source "${RETRO_HA_REPO_ROOT}/scripts/lib/common.sh"

if retro_ha_is_sourced; then
  echo sourced
else
  echo executed
fi
SH
  chmod +x "$script"

  run bash "$script"
  assert_success

  run bash -c "source '$script'"
  assert_success

  # root branches
  unset RETRO_HA_ROOT
  run retro_ha_root
  assert_success

  RETRO_HA_ROOT="$TEST_ROOT/"
  run retro_ha_root
  assert_success

  # path branches
  RETRO_HA_ROOT="$TEST_ROOT"
  run retro_ha_path "relative"
  assert_success
  RETRO_HA_ROOT="/"
  run retro_ha_path "/etc/hosts"
  assert_success
  RETRO_HA_ROOT="$TEST_ROOT"
  run retro_ha_path "/etc/hosts"
  assert_success

  # dirname branches
  run retro_ha_dirname ""
  assert_success
  run retro_ha_dirname "foo"
  assert_success
  run retro_ha_dirname "foo/bar"
  assert_success
  run retro_ha_dirname "/foo"
  assert_success
  run retro_ha_dirname "foo/bar/"
  assert_success

  # record_call branches
  export RETRO_HA_CALLS_FILE="$TEST_ROOT/calls-primary.log"
  export RETRO_HA_CALLS_FILE_APPEND="$TEST_ROOT/calls-append.log"
  record_call "hello"

  unset RETRO_HA_CALLS_FILE
  record_call "no-primary"

  export RETRO_HA_CALLS_FILE="$TEST_ROOT/calls-primary.log"
  unset RETRO_HA_CALLS_FILE_APPEND
  record_call "no-append"

  # run_cmd branches
  export RETRO_HA_DRY_RUN=1
  run run_cmd echo hi
  assert_success

  export RETRO_HA_DRY_RUN=0
  run run_cmd echo hi
  assert_success

  # realpath
  run retro_ha_realpath_m "a/../b"
  assert_success

  # logging.sh branches
  source "$RETRO_HA_REPO_ROOT/scripts/lib/logging.sh"

  unset RETRO_HA_LOG_PREFIX
  run retro_ha_log_prefix
  assert_success

  RETRO_HA_LOG_PREFIX="x"
  run retro_ha_log_prefix
  assert_success

  run log "hello"
  assert_success

  run warn "hello"
  assert_success

  run bash -c '
    set -euo pipefail
    source "$1"
    export RETRO_HA_PATH_COVERAGE=1
    export RETRO_HA_CALLS_FILE_APPEND="$2"
    die "boom"
  ' bash "$RETRO_HA_REPO_ROOT/scripts/lib/logging.sh" "$TEST_ROOT/path-log.log"
  assert_failure
}
