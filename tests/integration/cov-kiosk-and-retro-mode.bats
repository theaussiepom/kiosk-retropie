#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
	export RETRO_HA_DRY_RUN=1
	export XDG_RUNTIME_DIR="$TEST_ROOT/run/user/1000"
	mkdir -p "$XDG_RUNTIME_DIR"
}


teardown() {
	teardown_test_root
}

@test "ha-kiosk fails if HA_URL missing" {
	unset HA_URL
	run /bin/bash "$RETRO_HA_REPO_ROOT/scripts/mode/ha-kiosk.sh"
	assert_failure
}

@test "ha-kiosk chooses chromium-browser when present" {
	export HA_URL="http://example.local"

	# Use isolated path so chromium-browser is the only chromium candidate.
	make_isolated_path_with_stubs dirname chromium-browser xinit getent id

	run /bin/bash "$RETRO_HA_REPO_ROOT/scripts/mode/ha-kiosk.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "write_file $XDG_RUNTIME_DIR/retro-ha/ha-xinitrc"
	assert_file_contains "$TEST_ROOT/calls.log" "exec xinit"
}

@test "ha-kiosk writes xinitrc when not dry-run" {
	export HA_URL="http://example.local"
	export RETRO_HA_DRY_RUN=0

	# Use isolated path so we control chromium and xinit.
	make_isolated_path_with_stubs dirname chromium-browser xinit

	run /bin/bash "$RETRO_HA_REPO_ROOT/scripts/mode/ha-kiosk.sh"
	assert_success

	# xinitrc should be written in the runtime dir.
	[ -f "$XDG_RUNTIME_DIR/retro-ha/ha-xinitrc" ]
	assert_file_contains "$XDG_RUNTIME_DIR/retro-ha/ha-xinitrc" 'exec "chromium-browser"'
}

@test "ha-kiosk fails if no chromium binary" {
	export HA_URL="http://example.local"
	make_isolated_path_with_stubs dirname xinit getent id
	run /bin/bash "$RETRO_HA_REPO_ROOT/scripts/mode/ha-kiosk.sh"
	assert_failure
	assert_output --partial "Chromium not found"
}

@test "retro-mode exits 0 when emulationstation missing" {
	# Isolate PATH so emulationstation is not found.
	make_isolated_path_with_stubs dirname xinit
	run /bin/bash "$RETRO_HA_REPO_ROOT/scripts/mode/retro-mode.sh"
	assert_success
}

@test "retro-mode fails when xinit missing" {
	make_isolated_path_with_stubs dirname emulationstation
	run /bin/bash "$RETRO_HA_REPO_ROOT/scripts/mode/retro-mode.sh"
	assert_failure
	assert_output --partial "xinit not found"
}

@test "retro-mode records xinit exec in dry-run when deps present" {
	make_isolated_path_with_stubs dirname xinit emulationstation
	run /bin/bash "$RETRO_HA_REPO_ROOT/scripts/mode/retro-mode.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "write_file $XDG_RUNTIME_DIR/retro-ha/retro-xinitrc"
	assert_file_contains "$TEST_ROOT/calls.log" "exec xinit"
}

@test "retro-mode writes xinitrc when not dry-run" {
	export RETRO_HA_DRY_RUN=0
	make_isolated_path_with_stubs dirname xinit emulationstation

	run /bin/bash "$RETRO_HA_REPO_ROOT/scripts/mode/retro-mode.sh"
	assert_success

	[ -f "$XDG_RUNTIME_DIR/retro-ha/retro-xinitrc" ]
	assert_file_contains "$XDG_RUNTIME_DIR/retro-ha/retro-xinitrc" 'exec /usr/bin/emulationstation'
}
