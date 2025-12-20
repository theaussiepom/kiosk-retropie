#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"

@test "logging warn path is covered" {
	run bash -c '
		set -euo pipefail
		source "$1"
		export RETRO_HA_LOG_PREFIX="test"
		warn "hello"
	' bash "$RETRO_HA_REPO_ROOT/scripts/lib/logging.sh"
	assert_success
	assert_output --partial "[warn]"
}

@test "logging die path is covered" {
	# die() should exit non-zero; run in a subshell so the test can assert.
	run bash -c 'source "$1"; die "nope"' bash "$RETRO_HA_REPO_ROOT/scripts/lib/logging.sh"
	assert_failure
	assert_output --partial "[error]"
}
