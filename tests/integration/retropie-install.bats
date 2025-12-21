#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
  setup_test_root
  export RETRO_HA_DRY_RUN=1
  export RETRO_HA_ALLOW_NON_ROOT=1

  # Ensure retropi home resolves under RETRO_HA_ROOT.
  export GETENT_PASSWD_RETROPI_LINE="retropi:x:1000:1000::${TEST_ROOT}/home/retropi:/bin/bash"
  mkdir -p "$TEST_ROOT/home/retropi"
}

teardown() {
  teardown_test_root
}

@test "install-retropie fails when user missing" {
  export RETRO_HA_ALLOW_NON_ROOT=1
  make_isolated_path_with_stubs dirname git sudo getent
  run bash "$RETRO_HA_REPO_ROOT/scripts/retropie/install-retropie.sh"
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH retropie-install:user-missing"
}

@test "install-retropie fails when git missing" {
  make_isolated_path_with_stubs dirname sudo getent id
  run bash "$RETRO_HA_REPO_ROOT/scripts/retropie/install-retropie.sh"
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH retropie-install:git-missing"
}

@test "install-retropie fails when sudo missing" {
  make_isolated_path_with_stubs dirname git getent id
  run bash "$RETRO_HA_REPO_ROOT/scripts/retropie/install-retropie.sh"
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH retropie-install:sudo-missing"
}

@test "install-retropie fails when home dir missing" {
  export GETENT_PASSWD_RETROPI_LINE="retropi:x:1000:1000::::/bin/bash"
  make_isolated_path_with_stubs dirname git sudo getent id
  run bash "$RETRO_HA_REPO_ROOT/scripts/retropie/install-retropie.sh"
  assert_failure
  assert_file_contains "$TEST_ROOT/calls.log" "PATH retropie-install:home-missing"
}

@test "install-retropie clone path in dry-run" {
  make_isolated_path_with_stubs dirname git sudo getent id
  run bash "$RETRO_HA_REPO_ROOT/scripts/retropie/install-retropie.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH retropie-install:clone"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH retropie-install:dry-run"
}

@test "install-retropie update path in dry-run" {
  mkdir -p "$TEST_ROOT/home/retropi/RetroPie-Setup/.git"
  make_isolated_path_with_stubs dirname git sudo getent id
  run bash "$RETRO_HA_REPO_ROOT/scripts/retropie/install-retropie.sh"
  assert_success
  assert_file_contains "$TEST_ROOT/calls.log" "PATH retropie-install:update"
  assert_file_contains "$TEST_ROOT/calls.log" "PATH retropie-install:dry-run"
}
