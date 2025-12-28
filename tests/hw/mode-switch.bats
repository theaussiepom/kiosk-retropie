#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
}

teardown() {
	teardown_test_root
}


assert_calls_contains() {
	local needle="$1"
	local expected="$needle"
	# systemctl stub logs with: printf 'systemctl %q\n' "$*"
	# which escapes spaces in the argument string. Normalize expectations so
	# callers can write readable strings.
	if [[ "$expected" == systemctl\ * ]]; then
		local arg_str="${expected#systemctl }"
		expected="systemctl $(printf '%q' "$arg_str")"
	fi
	assert_file_contains "$KIOSK_RETROPIE_CALLS_FILE" "$expected"
}

refute_file_contains() {
	local file="$1"
	local needle="$2"
	if assert_file_contains "$file" "$needle"; then
		return 1
	fi
	return 0
}

make_fake_input_device() {
	local dev_root="$TEST_ROOT/dev/input"
	local by_id="$dev_root/by-id"
	mkdir -p "$by_id"

	local fifo="$dev_root/event0"
	mkfifo "$fifo"

	# Name must match *event-joystick glob; realpath basename must start with "event".
	ln -sf "../event0" "$by_id/usb-fake-event-joystick"

	export RETROPIE_INPUT_BY_ID_DIR="$by_id"
	export FAKE_CONTROLLER_FIFO="$fifo"
}

emit_key_presses() {
	local fifo_path="$1"
	shift
	local codes=("$@")

	python3 - "$fifo_path" "${codes[@]}" <<'PY'
import errno
import os
import struct
import sys
import time

fifo_path = sys.argv[1]
codes = [int(c) for c in sys.argv[2:]]

fmt = "llHHi"
etype = 1
value = 1

payloads = []
sec = int(time.time())
usec = 0
for code in codes:
    payloads.append(struct.pack(fmt, sec, usec, etype, code, value))

end = time.time() + 5.0
fd = None
while time.time() < end:
    try:
        fd = os.open(fifo_path, os.O_WRONLY | os.O_NONBLOCK)
        break
    except OSError as e:
        if e.errno in (errno.ENXIO, errno.ENOENT):
            time.sleep(0.05)
            continue
        raise

if fd is None:
    raise SystemExit(f"timeout opening fifo for write: {fifo_path}")

try:
	for p in payloads:
		os.write(fd, p)
finally:
    os.close(fd)
PY
}

wait_for_exit() {
	local pid="$1"
	local timeout_sec="${2:-5}"
	local end=$((SECONDS + timeout_sec))
	while kill -0 "$pid" 2>/dev/null; do
		if (( SECONDS >= end )); then
			kill "$pid" 2>/dev/null || true
			sleep 0.1
			kill -9 "$pid" 2>/dev/null || true
			return 1
		fi
		sleep 0.05
	done
	return 0
}

@test "TTY listener: Start while kiosk active stops kiosk and starts retro" {
	make_fake_input_device
	local fifo="$FAKE_CONTROLLER_FIFO"

	local state_file="$TEST_ROOT/systemctl.state"
	echo ":kiosk.service:" >"$state_file"

	LISTENER_LOG="$TEST_ROOT/controller-listener-tty.log"
	RETROPIE_INPUT_BY_ID_DIR="$RETROPIE_INPUT_BY_ID_DIR" \
		RETROPIE_ACTION_DEBOUNCE_SEC=0 \
		RETROPIE_MAX_TRIGGERS=1 \
		RETROPIE_MAX_LOOPS=200 \
		SYSTEMCTL_STATE_FILE="$state_file" \
		bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/input/controller-listener-tty.sh" >"$LISTENER_LOG" 2>&1 &
	local pid=$!

	emit_key_presses "$fifo" 315

	wait_for_exit "$pid" 5

	assert_calls_contains "systemctl stop kiosk.service"
	assert_calls_contains "systemctl start retro-mode.service"
	# Conflicts simulation in stub should have made retro active and kiosk inactive.
	assert_file_contains "$state_file" ":retro-mode.service:"
	refute_file_contains "$state_file" ":kiosk.service:"
}

@test "TTY listener: Exit combo while Retro active stops retro and starts kiosk" {
	make_fake_input_device
	local fifo="$FAKE_CONTROLLER_FIFO"

	local state_file="$TEST_ROOT/systemctl.state"
	echo ":retro-mode.service:" >"$state_file"

	LISTENER_LOG="$TEST_ROOT/controller-listener-tty-combo.log"
	RETROPIE_INPUT_BY_ID_DIR="$RETROPIE_INPUT_BY_ID_DIR" \
		RETROPIE_ACTION_DEBOUNCE_SEC=0 \
		RETROPIE_MAX_TRIGGERS=1 \
		RETROPIE_MAX_LOOPS=200 \
		RETROPIE_EXIT_SEQUENCE_CODES=315,304 \
		RETROPIE_COMBO_WINDOW_SEC=5 \
		SYSTEMCTL_STATE_FILE="$state_file" \
		bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/input/controller-listener-tty.sh" >"$LISTENER_LOG" 2>&1 &
	local pid=$!

	# Start then A (single write so the listener sees the full sequence).
	emit_key_presses "$fifo" 315 304
	wait_for_exit "$pid" 5

	assert_calls_contains "systemctl stop retro-mode.service"
	assert_calls_contains "systemctl start kiosk.service"
	assert_file_contains "$state_file" ":kiosk.service:"
	refute_file_contains "$state_file" ":retro-mode.service:"
}

@test "Healthcheck: when no mode active, it fails over to Retro via enter-retro-mode" {
	local state_file="$TEST_ROOT/systemctl.state"
	echo ":" >"$state_file"

	run env \
		SYSTEMCTL_STATE_FILE="$state_file" \
		RETROPIE_SKIP_LEDCTL=1 \
		KIOSK_RETROPIE_LIBDIR="$KIOSK_RETROPIE_REPO_ROOT/scripts/mode" \
		"$KIOSK_RETROPIE_REPO_ROOT/scripts/healthcheck.sh"

	assert_success
	assert_calls_contains "systemctl stop kiosk.service"
	assert_calls_contains "systemctl start retro-mode.service"
	assert_file_contains "$state_file" ":retro-mode.service:"
}

@test "Units: Retro mode returns to kiosk on exit and kiosk failover is configured" {
	assert_file_contains "$KIOSK_RETROPIE_REPO_ROOT/systemd/retro-mode.service" "ExecStopPost=/bin/systemctl start kiosk.service"
	assert_file_contains "$KIOSK_RETROPIE_REPO_ROOT/systemd/kiosk.service" "OnFailure=kiosk-retropie-failover.service"
}
