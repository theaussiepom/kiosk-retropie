#!/usr/bin/env bats

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  # Create a minimal fake repo root for scripts to use.
  export RETRO_HA_ROOT
  RETRO_HA_ROOT="$(mktemp -d)"

  export RETRO_HA_LIBDIR=""
  export RETRO_HA_ETCDIR=""

  # Source library for retro_ha_path used by healthcheck.
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/common.sh"
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/logging.sh"
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/config.sh"

  # Source the script under test (safe: guarded main).
  source "${RETRO_HA_REPO_ROOT}/scripts/healthcheck.sh"
}

test_teardown() {
  rm -rf "${RETRO_HA_ROOT}" || true
}

@test "healthcheck_enter_retro_path prefers RETRO_HA_LIBDIR enter-retro-mode.sh" {
  local libdir
  libdir="$(mktemp -d)"
  mkdir -p "$libdir"
  printf '#!/usr/bin/env bash\necho libdir\n' >"$libdir/enter-retro-mode.sh"
  chmod +x "$libdir/enter-retro-mode.sh"

  RETRO_HA_LIBDIR="$libdir"

  run healthcheck_enter_retro_path "/does/not/matter"
  assert_success
  assert_output "$libdir/enter-retro-mode.sh"

  rm -rf "$libdir"
}

@test "healthcheck_enter_retro_path falls back to script dir enter-retro-mode.sh" {
  local d
  d="$(mktemp -d)"
  printf '#!/usr/bin/env bash\necho scriptdir\n' >"$d/enter-retro-mode.sh"
  chmod +x "$d/enter-retro-mode.sh"

  RETRO_HA_LIBDIR=""

  run healthcheck_enter_retro_path "$d"
  assert_success
  assert_output "$d/enter-retro-mode.sh"

  rm -rf "$d"
}

@test "healthcheck_enter_retro_path falls back to script dir mode/enter-retro-mode.sh" {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/mode"
  printf '#!/usr/bin/env bash\necho modedir\n' >"$d/mode/enter-retro-mode.sh"
  chmod +x "$d/mode/enter-retro-mode.sh"

  RETRO_HA_LIBDIR=""

  run healthcheck_enter_retro_path "$d"
  assert_success
  assert_output "$d/mode/enter-retro-mode.sh"

  rm -rf "$d"
}

@test "healthcheck_enter_retro_path final fallback uses retro_ha_path" {
  RETRO_HA_LIBDIR=""

  run healthcheck_enter_retro_path "/definitely/missing"
  assert_success
  assert_output "${RETRO_HA_ROOT}/usr/local/lib/retro-ha/enter-retro-mode.sh"
}
