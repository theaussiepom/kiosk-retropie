#!/usr/bin/env bats

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  export RETRO_HA_ROOT
  RETRO_HA_ROOT="$(mktemp -d)"

  source "${RETRO_HA_REPO_ROOT}/scripts/leds/ledctl.sh"
}

test_teardown() {
  rm -rf "${RETRO_HA_ROOT}" || true
}

@test "trigger_supported matches desired trigger even when bracketed" {
  local f
  f="${RETRO_HA_ROOT}/trigger"
  printf 'none [mmc0] timer heartbeat\n' >"$f"

  run trigger_supported "$f" "mmc0"
  assert_success
}

@test "trigger_supported rejects partial-word matches" {
  local f
  f="${RETRO_HA_ROOT}/trigger"
  printf 'none [mmc0] timer\n' >"$f"

  run trigger_supported "$f" "mmc"
  assert_failure
}

@test "trigger_supported fails when file missing" {
  run trigger_supported "${RETRO_HA_ROOT}/does-not-exist" "mmc0"
  assert_failure
}
