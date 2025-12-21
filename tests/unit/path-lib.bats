#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/common.sh"
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/path.sh"
}

@test "retro_ha_path_is_under true when equal" {
  run retro_ha_path_is_under "/mnt/retro-ha-roms" "/mnt/retro-ha-roms"
  assert_success
}

@test "retro_ha_path_is_under true when child" {
  run retro_ha_path_is_under "/mnt/retro-ha-roms" "/mnt/retro-ha-roms/nes"
  assert_success
}

@test "retro_ha_path_is_under false for prefix trap" {
  run retro_ha_path_is_under "/mnt/retro-ha-roms" "/mnt/retro-ha-roms2"
  assert_failure
}

@test "retro_ha_path_is_under normalizes .. segments" {
  run retro_ha_path_is_under "/mnt/retro-ha-roms" "/mnt/retro-ha-roms/../retro-ha-roms/snes"
  assert_success
}

@test "retro_ha_path_is_under treats base '/' as parent of all" {
  run retro_ha_path_is_under "/" "/etc/retro-ha/config.env"
  assert_success
}
