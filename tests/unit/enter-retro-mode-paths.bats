#!/usr/bin/env bats

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  export RETRO_HA_ROOT
  RETRO_HA_ROOT="$(mktemp -d)"

  # Source the script under test (guarded main).
  source "${RETRO_HA_REPO_ROOT}/scripts/mode/enter-retro-mode.sh"
}

test_teardown() {
  rm -rf "${RETRO_HA_ROOT}" || true
}

@test "retro_ha_ledctl_path prefers RETRO_HA_LIBDIR when executable exists" {
  local libdir
  libdir="$(mktemp -d)"
  printf '#!/usr/bin/env bash\n' >"$libdir/ledctl.sh"
  chmod +x "$libdir/ledctl.sh"

  RETRO_HA_LIBDIR="$libdir"

  run retro_ha_ledctl_path "/does/not/matter"
  assert_success
  assert_output "$libdir/ledctl.sh"

  rm -rf "$libdir"
}

@test "retro_ha_ledctl_path falls back to <script_dir>/ledctl.sh" {
  local d
  d="$(mktemp -d)"
  printf '#!/usr/bin/env bash\n' >"$d/ledctl.sh"
  chmod +x "$d/ledctl.sh"

  RETRO_HA_LIBDIR=""

  run retro_ha_ledctl_path "$d"
  assert_success
  assert_output "$d/ledctl.sh"

  rm -rf "$d"
}

@test "retro_ha_ledctl_path falls back to <script_dir>/../leds/ledctl.sh" {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/../leds" 2>/dev/null || true

  # Ensure the sibling leds dir exists under a controlled temp tree.
  local root
  root="$(mktemp -d)"
  mkdir -p "$root/mode" "$root/leds"
  printf '#!/usr/bin/env bash\n' >"$root/leds/ledctl.sh"
  chmod +x "$root/leds/ledctl.sh"

  RETRO_HA_LIBDIR=""

  run retro_ha_ledctl_path "$root/mode"
  assert_success
  assert_output "$root/mode/../leds/ledctl.sh"

  rm -rf "$root"
}

@test "retro_ha_ledctl_path final fallback uses retro_ha_libdir" {
  RETRO_HA_LIBDIR=""

  run retro_ha_ledctl_path "/definitely/missing"
  assert_success
  assert_output "${RETRO_HA_ROOT}/usr/local/lib/retro-ha/ledctl.sh"
}
