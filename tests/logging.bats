#!/usr/bin/env bats

load 'vendor/bats-support/load'
load 'vendor/bats-assert/load'

@test "logging warn path is covered" {
	run bash -c '
		set -euo pipefail
		source "$1"
		export RETRO_HA_LOG_PREFIX="test"
		warn "hello"
	' bash "$BATS_TEST_DIRNAME/../scripts/lib/logging.sh"
	assert_success
	assert_output --partial "[warn]"
}
