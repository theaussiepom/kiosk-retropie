#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
	export RETRO_HA_DRY_RUN=1

	# Provide a fake ledctl in repo layout so enter-retro-mode finds it.
	mkdir -p "$TEST_ROOT/tmp"
}

teardown() {
	teardown_test_root
}

@test "enter-ha-mode stops retro and starts ha" {
	run bash "$RETRO_HA_REPO_ROOT/scripts/mode/enter-ha-mode.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "systemctl stop retro-mode.service"
	assert_file_contains "$TEST_ROOT/calls.log" "systemctl start ha-kiosk.service"
}

@test "enter-retro-mode stops ha and starts retro" {
	# Ensure enter-retro-mode can find ledctl via repo layout.
	# It will be recorded (dry-run) rather than executed.
	run bash "$RETRO_HA_REPO_ROOT/scripts/mode/enter-retro-mode.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "systemctl stop ha-kiosk.service"
	assert_file_contains "$TEST_ROOT/calls.log" "systemctl start retro-mode.service"
	assert_file_contains "$TEST_ROOT/calls.log" "ledctl.sh all on"
}

@test "enter-retro-mode ledctl path selection covers all branches" {
	source "$RETRO_HA_REPO_ROOT/scripts/mode/enter-retro-mode.sh"

	# Case 1: RETRO_HA_LIBDIR/ledctl.sh is executable.
	local libdir="$TEST_ROOT/lib"
	mkdir -p "$libdir"
	echo '#!/usr/bin/env bash' >"$libdir/ledctl.sh"
	echo 'exit 0' >>"$libdir/ledctl.sh"
	chmod +x "$libdir/ledctl.sh"
	RETRO_HA_LIBDIR="$libdir"
	run retro_ha_ledctl_path
	assert_success
	assert_output "$libdir/ledctl.sh"

	# Case 2: SCRIPT_DIR/ledctl.sh exists.
	unset RETRO_HA_LIBDIR
	SCRIPT_DIR="$TEST_ROOT/mode"
	mkdir -p "$SCRIPT_DIR"
	echo '#!/usr/bin/env bash' >"$SCRIPT_DIR/ledctl.sh"
	echo 'exit 0' >>"$SCRIPT_DIR/ledctl.sh"
	chmod +x "$SCRIPT_DIR/ledctl.sh"
	run retro_ha_ledctl_path
	assert_success
	assert_output "$SCRIPT_DIR/ledctl.sh"

	# Case 3: SCRIPT_DIR/../leds/ledctl.sh exists.
	rm -f "$SCRIPT_DIR/ledctl.sh"
	mkdir -p "$TEST_ROOT/leds"
	echo '#!/usr/bin/env bash' >"$TEST_ROOT/leds/ledctl.sh"
	echo 'exit 0' >>"$TEST_ROOT/leds/ledctl.sh"
	chmod +x "$TEST_ROOT/leds/ledctl.sh"
	run retro_ha_ledctl_path
	assert_success
	assert_output --partial "/leds/ledctl.sh"

	# Case 4: fallback path when nothing exists (not executable).
	rm -f "$TEST_ROOT/leds/ledctl.sh"
	run retro_ha_ledctl_path
	assert_success
	assert_output --partial "/usr/local/lib/retro-ha/ledctl.sh"
}

@test "enter-retro-mode skips led forcing when ledctl missing" {
	# Run in a subshell with SCRIPT_DIR set so that none of the candidate ledctl
	# paths exist.
	export RETRO_HA_DRY_RUN=1
	unset RETRO_HA_LIBDIR

	local isolated_dir="$TEST_ROOT/isolated/mode"
	mkdir -p "$isolated_dir"

	run bash -c '
		set -euo pipefail
		source "$1"
		SCRIPT_DIR="$2"
		main
	' bash "$RETRO_HA_REPO_ROOT/scripts/mode/enter-retro-mode.sh" "$isolated_dir"
	assert_success
	# Should still switch modes.
	assert_file_contains "$TEST_ROOT/calls.log" "systemctl stop ha-kiosk.service"
	assert_file_contains "$TEST_ROOT/calls.log" "systemctl start retro-mode.service"
	# But should not attempt to run ledctl.
	if [[ -f "$TEST_ROOT/calls.log" ]]; then
		! /usr/bin/grep -Fq -- "ledctl.sh all on" "$TEST_ROOT/calls.log"
	fi
}
