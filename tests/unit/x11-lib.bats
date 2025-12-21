#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

# shellcheck source=../vendor/bats-support/load
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
# shellcheck source=../vendor/bats-assert/load
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  export RETRO_HA_ROOT
  RETRO_HA_ROOT="$(mktemp -d)"

  # shellcheck source=../../scripts/lib/common.sh
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/common.sh"
  # shellcheck source=../../scripts/lib/x11.sh
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/x11.sh"

  unset XDG_RUNTIME_DIR || true
}

test_teardown() {
  rm -rf "${RETRO_HA_ROOT}" || true
}

@test "retro_ha_runtime_dir uses XDG_RUNTIME_DIR when set" {
  export XDG_RUNTIME_DIR="/run/user/999"
  run retro_ha_runtime_dir 123
  assert_success
  assert_output "/run/user/999"
}

@test "retro_ha_runtime_dir falls back to retro_ha_path /run/user/<uid>" {
  RETRO_HA_ROOT="/tmp/testroot"
  run retro_ha_runtime_dir 123
  assert_success
  assert_output "/tmp/testroot/run/user/123"
}

@test "retro_ha_state_dir appends /retro-ha" {
  run retro_ha_state_dir "/run/user/1000"
  assert_success
  assert_output "/run/user/1000/retro-ha"
}

@test "retro_ha_xinitrc_path joins state_dir + name" {
  run retro_ha_xinitrc_path "/run/user/1000/retro-ha" "ha-xinitrc"
  assert_success
  assert_output "/run/user/1000/retro-ha/ha-xinitrc"
}

@test "retro_ha_x_lock_paths yields both lock and socket paths" {
  RETRO_HA_ROOT="/tmp/testroot"
  run retro_ha_x_lock_paths ":0"
  assert_success
  assert_output $'/tmp/testroot/tmp/.X0-lock\n/tmp/testroot/tmp/.X11-unix/X0'
}

@test "retro_ha_xinit_exec_record formats xinit command" {
  run retro_ha_xinit_exec_record "/r/ha-xinitrc" ":0" "7"
  assert_success
  assert_output "exec xinit /r/ha-xinitrc -- /usr/lib/xorg/Xorg :0 vt7 -nolisten tcp -keeptty"
}

@test "retro_ha_xinitrc_prelude contains rotation guard and xset block" {
  run retro_ha_xinitrc_prelude
  assert_success
  assert_output --partial "command -v xset"
  assert_output --partial "RETRO_HA_SCREEN_ROTATION"
  assert_output --partial "command -v xrandr"
}
