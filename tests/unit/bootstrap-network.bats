#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  export RETRO_HA_ROOT
  RETRO_HA_ROOT="$(mktemp -d)"

  export RETRO_HA_CALLS_FILE
  RETRO_HA_CALLS_FILE="${RETRO_HA_ROOT}/calls.txt"

  local old_path="$PATH"
  export _OLD_PATH="$old_path"
  PATH="${RETRO_HA_REPO_ROOT}/tests/stubs:$PATH"

  # Source script under test (guarded main).
  source "${RETRO_HA_REPO_ROOT}/scripts/bootstrap.sh"
}

test_teardown() {
  PATH="${_OLD_PATH}"
  rm -rf "${RETRO_HA_ROOT}" || true
}

@test "network_ok succeeds when getent and curl succeed" {
  export GETENT_HOSTS_EXIT_CODE=0
  export CURL_EXIT_CODE=0

  run network_ok
  assert_success

  run cat "$RETRO_HA_CALLS_FILE"
  assert_success
  assert_output --partial "getent"
  assert_output --partial "github.com"
  assert_output --partial "curl"
  assert_output --partial "https://github.com"
}

@test "network_ok fails fast when getent fails (curl not called)" {
  export GETENT_HOSTS_EXIT_CODE=2
  export CURL_EXIT_CODE=0

  run network_ok
  assert_failure

  run cat "$RETRO_HA_CALLS_FILE"
  assert_success
  assert_output --partial "getent"
  assert_output --partial "github.com"
  refute_output --partial "curl"
}

@test "network_ok fails when curl fails" {
  export GETENT_HOSTS_EXIT_CODE=0
  export CURL_EXIT_CODE=22

  run network_ok
  assert_failure

  run cat "$RETRO_HA_CALLS_FILE"
  assert_success
  assert_output --partial "getent"
  assert_output --partial "github.com"
  assert_output --partial "curl"
  assert_output --partial "https://github.com"
}
