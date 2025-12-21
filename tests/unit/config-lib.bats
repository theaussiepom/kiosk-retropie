#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  export RETRO_HA_ROOT
  RETRO_HA_ROOT="$(mktemp -d)"

  source "${RETRO_HA_REPO_ROOT}/scripts/lib/common.sh"
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/config.sh"

  unset RETRO_HA_CONFIG_ENV || true
}

test_teardown() {
  rm -rf "${RETRO_HA_ROOT}" || true
}

@test "retro_ha_config_env_path uses RETRO_HA_CONFIG_ENV when set" {
  RETRO_HA_CONFIG_ENV="/tmp/special/config.env"
  run retro_ha_config_env_path
  assert_success
  assert_output "/tmp/special/config.env"
}

@test "retro_ha_config_env_path defaults under RETRO_HA_ROOT" {
  RETRO_HA_ROOT="/tmp/testroot"
  run retro_ha_config_env_path
  assert_success
  assert_output "/tmp/testroot/etc/retro-ha/config.env"
}

@test "load_config_env sources file when present" {
  local env_file
  env_file="${RETRO_HA_ROOT}/custom.env"

  printf 'FOO=bar\nBAZ=qux\n' >"$env_file"
  RETRO_HA_CONFIG_ENV="$env_file"

  load_config_env

  [ "${FOO}" = "bar" ]
  [ "${BAZ}" = "qux" ]
}

@test "load_config_env is a no-op when file missing" {
  export RETRO_HA_CONFIG_ENV="${RETRO_HA_ROOT}/missing.env"

  unset FOO || true
  load_config_env

  [ -z "${FOO:-}" ]
}
