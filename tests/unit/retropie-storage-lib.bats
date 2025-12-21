#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  export RETRO_HA_ROOT
  RETRO_HA_ROOT="$(mktemp -d)"

  export RETRO_HA_CALLS_FILE
  RETRO_HA_CALLS_FILE="${RETRO_HA_ROOT}/calls.txt"
  export RETRO_HA_CALLS_FILE_APPEND=""

  source "${RETRO_HA_REPO_ROOT}/scripts/lib/common.sh"
  source "${RETRO_HA_REPO_ROOT}/scripts/lib/path.sh"
  source "${RETRO_HA_REPO_ROOT}/scripts/retropie/configure-retropie-storage.sh"

  export RETRO_HA_DRY_RUN=0
}

test_teardown() {
  rm -rf "${RETRO_HA_ROOT}" || true
}

@test "ensure_kv_line appends key when missing" {
  local f
  f="${RETRO_HA_ROOT}/retroarch.cfg"

  printf 'foo = "bar"\n' >"$f"

  ensure_kv_line "$f" "savefile_directory" "/saves"

  run grep -E '^savefile_directory[[:space:]]*=' "$f"
  assert_success
  assert_output 'savefile_directory = "/saves"'
}

@test "ensure_kv_line replaces existing key" {
  local f
  f="${RETRO_HA_ROOT}/retroarch.cfg"

  printf 'savefile_directory = "/old"\nother = "x"\n' >"$f"

  ensure_kv_line "$f" "savefile_directory" "/new"

  run cat "$f"
  assert_success
  assert_output $'savefile_directory = "/new"\nother = "x"'
}

@test "ensure_kv_line dry-run records write_kv and does not modify file" {
  local f
  f="${RETRO_HA_ROOT}/retroarch.cfg"

  printf 'savefile_directory = "/old"\n' >"$f"

  RETRO_HA_DRY_RUN=1
  ensure_kv_line "$f" "savefile_directory" "/new"

  run cat "$f"
  assert_success
  assert_output 'savefile_directory = "/old"'

  run cat "$RETRO_HA_CALLS_FILE"
  assert_success
  assert_output --partial "write_kv ${f} savefile_directory"
}
