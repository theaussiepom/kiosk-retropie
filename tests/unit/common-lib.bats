#!/usr/bin/env bats

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/common.sh"

  export RETRO_HA_ROOT
  RETRO_HA_ROOT="$(mktemp -d)"

  export RETRO_HA_CALLS_FILE
  RETRO_HA_CALLS_FILE="${RETRO_HA_ROOT}/calls/log.txt"

  export RETRO_HA_CALLS_FILE_APPEND
  RETRO_HA_CALLS_FILE_APPEND="${RETRO_HA_ROOT}/calls/all.txt"
  export RETRO_HA_DRY_RUN=0
}

test_teardown() {
  rm -rf "${RETRO_HA_ROOT}" || true
}

@test "retro_ha_root normalizes trailing slash" {
  RETRO_HA_ROOT="/tmp/retro-ha/"
  run retro_ha_root
  assert_success
  assert_output "/tmp/retro-ha"
}

@test "retro_ha_path prefixes absolute paths with RETRO_HA_ROOT" {
  RETRO_HA_ROOT="/tmp/retro-ha"
  run retro_ha_path "/etc/foo"
  assert_success
  assert_output "/tmp/retro-ha/etc/foo"
}

@test "retro_ha_path leaves absolute paths unchanged when RETRO_HA_ROOT is /" {
  RETRO_HA_ROOT="/"
  run retro_ha_path "/etc/foo"
  assert_success
  assert_output "/etc/foo"
}

@test "retro_ha_path leaves relative paths unchanged" {
  RETRO_HA_ROOT="/tmp/retro-ha"
  run retro_ha_path "relative/path"
  assert_success
  assert_output "relative/path"
}

@test "retro_ha_dirname matches basic dirname cases" {
  run retro_ha_dirname ""
  assert_success
  assert_output "."

  run retro_ha_dirname "foo"
  assert_success
  assert_output "."

  run retro_ha_dirname "foo/bar"
  assert_success
  assert_output "foo"

  run retro_ha_dirname "/foo"
  assert_success
  assert_output "/"

  run retro_ha_dirname "/foo/bar/"
  assert_success
  assert_output "/foo"

  run retro_ha_dirname "/"
  assert_success
  assert_output "/"
}

@test "record_call writes to calls file and append file" {
  run record_call "hello" "world"
  assert_success

  [ -f "$RETRO_HA_CALLS_FILE" ]
  [ -f "$RETRO_HA_CALLS_FILE_APPEND" ]

  run cat "$RETRO_HA_CALLS_FILE"
  assert_success
  assert_output "hello world"

  run cat "$RETRO_HA_CALLS_FILE_APPEND"
  assert_success
  assert_output "hello world"
}

@test "cover_path records PATH entries when enabled" {
  RETRO_HA_PATH_COVERAGE=1

  run cover_path "FOO"
  assert_success

  run cat "$RETRO_HA_CALLS_FILE"
  assert_success
  assert_output "PATH FOO"
}

@test "run_cmd records calls in dry-run mode and returns success" {
  RETRO_HA_DRY_RUN=1

  run run_cmd false
  assert_success

  run cat "$RETRO_HA_CALLS_FILE"
  assert_success
  assert_output "false"
}

@test "retro_ha_is_sourced detects sourced top-level script" {
  local script
  script="${RETRO_HA_ROOT}/sourced-check.sh"

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

  # Executed normally: should be 'executed'
  run bash "$script"
  assert_success
  assert_output "executed"

  # Sourced into an interactive shell: should be 'sourced'
  run bash -c "source '$script'"
  assert_success
  assert_output "sourced"
}
