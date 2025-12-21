#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
  setup_test_root
  export RETRO_HA_ALLOW_NON_ROOT=1
  export RETRO_HA_DRY_RUN=1
}

test_teardown() {
  teardown_test_root
}

@test "install branch coverage: marker present early" {
  export RETRO_HA_INSTALLED_MARKER="$TEST_ROOT/var/lib/retro-ha/installed"
  : >"$RETRO_HA_INSTALLED_MARKER"
  run bash "$RETRO_HA_REPO_ROOT/scripts/install.sh"
  assert_success
}

@test "install branch coverage: root ok" {
  export RETRO_HA_ALLOW_NON_ROOT=0
  export RETRO_HA_EUID_OVERRIDE=0
  export RETRO_HA_DRY_RUN=1
  export RETRO_HA_INSTALLED_MARKER="$TEST_ROOT/var/lib/retro-ha/installed"
  : >"$RETRO_HA_INSTALLED_MARKER"

  run bash "$RETRO_HA_REPO_ROOT/scripts/install.sh"
  assert_success
}

@test "install branch coverage: chromium none" {
  # Exercise the install_packages chromium fallback branch.
  export RETRO_HA_ALLOW_NON_ROOT=1
  export RETRO_HA_DRY_RUN=1
  export ID_RETROPI_EXISTS=1
  export APT_CACHE_HAS_CHROMIUM_BROWSER=0
  export APT_CACHE_HAS_CHROMIUM=0
  export RETRO_HA_INSTALL_RETROPIE=0

  rm -f "$TEST_ROOT/var/lib/retro-ha/installed"
  unset RETRO_HA_STUB_FLOCK_TOUCH_MARKER || true
  unset RETRO_HA_STUB_FLOCK_EXIT_CODE || true

  run bash "$RETRO_HA_REPO_ROOT/scripts/install.sh"
  assert_success
}

@test "install branch coverage: root required" {
  export RETRO_HA_ALLOW_NON_ROOT=0
  export RETRO_HA_EUID_OVERRIDE=1000
  export RETRO_HA_DRY_RUN=1

  run bash "$RETRO_HA_REPO_ROOT/scripts/install.sh"
  assert_failure
  assert_output --partial "Must run as root"
}

@test "install branch coverage: lock busy" {
  rm -f "$TEST_ROOT/var/lib/retro-ha/installed"
  export RETRO_HA_STUB_FLOCK_EXIT_CODE=1
  run bash "$RETRO_HA_REPO_ROOT/scripts/install.sh"
  assert_failure
  assert_output --partial "Another installer instance is running"
}

@test "install branch coverage: marker appears after lock" {
  export RETRO_HA_INSTALLED_MARKER="$TEST_ROOT/var/lib/retro-ha/installed"
  rm -f "$RETRO_HA_INSTALLED_MARKER"
  export RETRO_HA_STUB_FLOCK_EXIT_CODE=0
  export RETRO_HA_STUB_FLOCK_TOUCH_MARKER=1

  run bash "$RETRO_HA_REPO_ROOT/scripts/install.sh"
  assert_success
  assert_output --partial "marker appeared while waiting for lock"
}

@test "install branch coverage: user exists + chromium browser package" {
  export ID_RETROPI_EXISTS=1
  export APT_CACHE_HAS_CHROMIUM_BROWSER=1
  export APT_CACHE_HAS_CHROMIUM=0
  export RETRO_HA_INSTALL_RETROPIE=0

  rm -f "$TEST_ROOT/var/lib/retro-ha/installed"
  unset RETRO_HA_STUB_FLOCK_TOUCH_MARKER || true
  unset RETRO_HA_STUB_FLOCK_EXIT_CODE || true

  run bash "$RETRO_HA_REPO_ROOT/scripts/install.sh"
  assert_success
}

@test "install branch coverage: user created + chromium package + optional retropie" {
  export ID_RETROPI_EXISTS=0
  export APT_CACHE_HAS_CHROMIUM_BROWSER=0
  export APT_CACHE_HAS_CHROMIUM=1
  export RETRO_HA_INSTALL_RETROPIE=1

  rm -f "$TEST_ROOT/var/lib/retro-ha/installed"
  unset RETRO_HA_STUB_FLOCK_TOUCH_MARKER || true
  unset RETRO_HA_STUB_FLOCK_EXIT_CODE || true

  run bash "$RETRO_HA_REPO_ROOT/scripts/install.sh"
  assert_success

  assert_file_contains "$TEST_ROOT/calls.log" "useradd"
}

@test "install branch coverage: chromium none + write marker real" {
  # Source safely (install.sh is guarded) and call write_marker with DRY_RUN=0.
  export ID_RETROPI_EXISTS=1
  export APT_CACHE_HAS_CHROMIUM_BROWSER=0
  export APT_CACHE_HAS_CHROMIUM=0
  export RETRO_HA_DRY_RUN=0
  export RETRO_HA_INSTALLED_MARKER="$TEST_ROOT/var/lib/retro-ha/installed-real"

  source "$RETRO_HA_REPO_ROOT/scripts/install.sh"

  run write_marker
  assert_success
  [ -s "$RETRO_HA_INSTALLED_MARKER" ]
}
