#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

load "${KIOSK_RETROPIE_REPO_ROOT}/tests/vendor/bats-support/load"
load "${KIOSK_RETROPIE_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  export KIOSK_RETROPIE_ROOT
  KIOSK_RETROPIE_ROOT="$(mktemp -d)"

  # Source script under test (guarded main).
  source "${KIOSK_RETROPIE_REPO_ROOT}/scripts/mode/kiosk.sh"
}

test_teardown() {
  rm -rf "${KIOSK_RETROPIE_ROOT}" || true
}

@test "chromium_bin prefers chromium when both exist" {
  local bindir
  bindir="$(mktemp -d)"
  ln -s "${KIOSK_RETROPIE_REPO_ROOT}/tests/stubs/chromium" "$bindir/chromium"
  ln -s "${KIOSK_RETROPIE_REPO_ROOT}/tests/stubs/chromium-browser" "$bindir/chromium-browser"

  local old_path="$PATH"
  PATH="$bindir:$old_path"

  run chromium_bin
  PATH="$old_path"

  assert_success
  assert_output "chromium"

  rm -rf "$bindir"
}

@test "chromium_bin returns chromium-browser when chromium absent" {
  local bindir
  bindir="$(mktemp -d)"
  ln -s "${KIOSK_RETROPIE_REPO_ROOT}/tests/stubs/chromium-browser" "$bindir/chromium-browser"

  local old_path="$PATH"
  PATH="$bindir:$old_path"

  run chromium_bin
  PATH="$old_path"

  assert_success
  assert_output "chromium-browser"

  rm -rf "$bindir"
}

@test "chromium_bin returns chromium when chromium-browser absent" {
  local bindir
  bindir="$(mktemp -d)"
  ln -s "${KIOSK_RETROPIE_REPO_ROOT}/tests/stubs/chromium" "$bindir/chromium"

  local old_path="$PATH"
  # Ensure host-installed chromium-browser can't win resolution.
  PATH="$bindir"

  run chromium_bin
  PATH="$old_path"

  assert_success
  assert_output "chromium"

  rm -rf "$bindir"
}

@test "chromium_bin fails when neither chromium-browser nor chromium exist" {
  local bindir
  bindir="$(mktemp -d)"

  local old_path="$PATH"
  PATH="$bindir"

  run chromium_bin
  PATH="$old_path"

  assert_failure

  rm -rf "$bindir"
}
