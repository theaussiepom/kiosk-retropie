#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"

@test "systemd unit ExecStart references stay under /usr/local/lib/retro-ha" {
	# -h: no filename prefix, -o: only matching part, -E: extended regex (portable for '+').
	run grep -RhoE '^ExecStart=[^ ]+' "$RETRO_HA_REPO_ROOT/systemd"
	assert_success

	while IFS= read -r line; do
		# line format: ExecStart=/path
		path="${line#ExecStart=}"
		if [[ "$path" != /usr/local/lib/retro-ha/* ]]; then
			echo "Unexpected ExecStart path: $path" >&2
			return 1
		fi
	done <<<"$output"
}

@test "ha-kiosk and retro-mode units exist" {
	[ -f "$RETRO_HA_REPO_ROOT/systemd/ha-kiosk.service" ]
	[ -f "$RETRO_HA_REPO_ROOT/systemd/retro-mode.service" ]
}
