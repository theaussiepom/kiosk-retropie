#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"

setup() {
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR" || true
}

@test "recalc-path-coverage computes per-suite and union uncovered counts" {
  local required="$TMPDIR/required.txt"
  cat >"$required" <<'EOF'
lib-a:one
lib-b:two
script:x
script:y
EOF

  local unit_log="$TMPDIR/unit.log"
  cat >"$unit_log" <<'EOF'
PATH lib-a:one
PATH lib-b:two
EOF

  local int_log="$TMPDIR/int.log"
  cat >"$int_log" <<'EOF'
PATH script:x
EOF

  run "$RETRO_HA_REPO_ROOT/tests/bin/recalc-path-coverage.sh" \
    --no-run \
    --required-file "$required" \
    --unit-log "$unit_log" \
    --integration-log "$int_log"

  assert_success
  assert_line --index 0 "required_ids_total=4"
  assert_line --index 1 "required_ids_unit=2"
  assert_line --index 2 "required_ids_integration=2"
  assert_line --index 3 "unit_uncovered_required_ids=0"
  assert_line --index 4 "integration_uncovered_required_ids=1"
  assert_line --index 5 "union_uncovered_required_ids=1"
}
