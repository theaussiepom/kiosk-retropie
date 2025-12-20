#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"
load "$RETRO_HA_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root

	# Deterministic behavior: no debounce and exit after first trigger.
	export RETRO_HA_START_DEBOUNCE_SEC=0
	export RETRO_HA_MAX_TRIGGERS=1
	# Safety: avoid infinite loops if something goes wrong.
	export RETRO_HA_MAX_LOOPS=200

	# Default to "not active" for services unless a test overrides.
	export SYSTEMCTL_ACTIVE_HA=1
	export SYSTEMCTL_ACTIVE_RETRO=1
}

teardown() {
	# Best-effort cleanup if a background listener is still running.
	if [[ -n "${LISTENER_PID:-}" ]] && kill -0 "$LISTENER_PID" 2>/dev/null; then
		kill "$LISTENER_PID" 2>/dev/null || true
		sleep 0.1
		kill -9 "$LISTENER_PID" 2>/dev/null || true
	fi

	teardown_test_root
}

make_fake_controller_fifo() {
	local by_id_dir="$TEST_ROOT/dev/input/by-id"
	mkdir -p "$by_id_dir"

	# Add one broken device symlink to exercise open-failed path.
	ln -s "$TEST_ROOT/dev/input/event-missing" "$by_id_dir/broken-event-joystick" || true

	local fifo="$TEST_ROOT/dev/input/event0"
	mkfifo "$fifo"

	# Name must match *event-joystick glob in the production scripts.
	ln -s "$fifo" "$by_id_dir/fake-event-joystick"

	export RETRO_HA_INPUT_BY_ID_DIR="$by_id_dir"
	export FAKE_CONTROLLER_FIFO="$fifo"
}

emit_start_press() {
	local fifo_path="$1"
	local code="${2:-315}"

	python3 - "$fifo_path" "$code" <<'PY'
import errno
import os
import struct
import sys
import time

fifo_path = sys.argv[1]
code = int(sys.argv[2])

fmt = "llHHi"  # must match listener scripts
sec = int(time.time())
usec = 0
etype = 1
value = 1
payload = struct.pack(fmt, sec, usec, etype, code, value)

# FIFO open semantics: open for write blocks until there is a reader.
# Use O_NONBLOCK and retry until the listener has opened the FIFO.
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
    os.write(fd, payload)
finally:
    os.close(fd)
PY
}

wait_for_exit() {
	local pid="$1"
	local timeout_sec="${2:-5}"
	local log_file="${3:-}"

	local end=$((SECONDS + timeout_sec))
	while kill -0 "$pid" 2>/dev/null; do
		if (( SECONDS >= end )); then
			echo "listener timed out; killing pid=$pid" >&2
			if [[ -n "$log_file" && -f "$log_file" ]]; then
				echo "--- listener output (timeout) ---" >&2
				sed -n '1,200p' "$log_file" >&2 || true
			fi
			kill "$pid" 2>/dev/null || true
			sleep 0.2
			kill -9 "$pid" 2>/dev/null || true
			return 1
		fi
		sleep 0.05
	done
	return 0
}

wait_for_log_pattern() {
	local file="$1"
	local pattern="$2"
	local timeout_sec="${3:-2}"

	local end=$((SECONDS + timeout_sec))
	while (( SECONDS < end )); do
		if [[ -f "$file" ]] && /usr/bin/grep -Fq -- "$pattern" "$file" 2>/dev/null; then
			return 0
		fi
		sleep 0.05
	done
	return 1
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

	if assert_file_contains "$TEST_ROOT/calls.log" "$expected"; then
		return 0
	fi

	echo "--- expected call missing ---" >&2
	echo "$expected" >&2
	echo "--- calls.log ---" >&2
	sed -n '1,200p' "$TEST_ROOT/calls.log" >&2 || true

	if [[ -n "${LISTENER_LOG:-}" && -f "${LISTENER_LOG:-}" ]]; then
		echo "--- listener log ---" >&2
		sed -n '1,200p' "$LISTENER_LOG" >&2 || true
	fi
	return 1
}

@test "HA mode listener: Start press starts retro-mode when HA active" {
	make_fake_controller_fifo
	local fifo="$FAKE_CONTROLLER_FIFO"

	# Preconditions:
	# - HA is active (exit 0)
	# - Retro is inactive (non-zero)
	export SYSTEMCTL_ACTIVE_HA=0
	export SYSTEMCTL_ACTIVE_RETRO=1

	LISTENER_LOG="$TEST_ROOT/controller-listener-ha.log"
	export LISTENER_LOG

	bash "$RETRO_HA_REPO_ROOT/scripts/input/controller-listener-ha-mode.sh" >"$LISTENER_LOG" 2>&1 &
	LISTENER_PID=$!
	export LISTENER_PID

	# Best-effort readiness check; emit_start_press will also retry FIFO open.
	wait_for_log_pattern "$LISTENER_LOG" "Listening on" 3 || true

	emit_start_press "$fifo" "${RETRO_HA_START_BUTTON_CODE:-315}"
	wait_for_exit "$LISTENER_PID" 5 "$LISTENER_LOG"

	assert_calls_contains "systemctl is-active --quiet ha-kiosk.service"
	assert_calls_contains "systemctl start retro-mode.service"

	# Sanity: should not stop HA in this mode.
	if assert_file_contains "$TEST_ROOT/calls.log" "systemctl $(printf '%q' 'stop ha-kiosk.service')"; then
		echo "unexpected stop ha-kiosk.service" >&2
		return 1
	fi
}

@test "HA mode listener: exits 0 when HA is not active" {
	# HA inactive => early exit 0
	export SYSTEMCTL_ACTIVE_HA=1

	# No devices needed; should short-circuit before scanning.
	run bash "$RETRO_HA_REPO_ROOT/scripts/input/controller-listener-ha-mode.sh"
	assert_success
}

@test "HA mode listener: exits 1 when no devices found" {
	export SYSTEMCTL_ACTIVE_HA=0
	export SYSTEMCTL_ACTIVE_RETRO=1

	local by_id_dir="$TEST_ROOT/dev/input/by-id"
	mkdir -p "$by_id_dir"
	export RETRO_HA_INPUT_BY_ID_DIR="$by_id_dir"

	run bash "$RETRO_HA_REPO_ROOT/scripts/input/controller-listener-ha-mode.sh"
	assert_failure
}

@test "TTY listener: Start press stops HA then starts retro-mode" {
	make_fake_controller_fifo
	local fifo="$FAKE_CONTROLLER_FIFO"

	# Preconditions: Retro is inactive so it doesn't early-return.
	export SYSTEMCTL_ACTIVE_RETRO=1

	LISTENER_LOG="$TEST_ROOT/controller-listener-tty.log"
	export LISTENER_LOG

	bash "$RETRO_HA_REPO_ROOT/scripts/input/controller-listener-tty.sh" >"$LISTENER_LOG" 2>&1 &
	LISTENER_PID=$!
	export LISTENER_PID

	wait_for_log_pattern "$LISTENER_LOG" "Listening on" 3 || true

	emit_start_press "$fifo" "${RETRO_HA_START_BUTTON_CODE:-315}"
	wait_for_exit "$LISTENER_PID" 5 "$LISTENER_LOG"

	assert_calls_contains "systemctl stop ha-kiosk.service"
	assert_calls_contains "systemctl start retro-mode.service"
}

@test "TTY listener: exits 1 when no devices found" {
	local by_id_dir="$TEST_ROOT/dev/input/by-id"
	mkdir -p "$by_id_dir"
	export RETRO_HA_INPUT_BY_ID_DIR="$by_id_dir"

	# Ensure it doesn't short-circuit on retro already active.
	export SYSTEMCTL_ACTIVE_RETRO=1

	run bash "$RETRO_HA_REPO_ROOT/scripts/input/controller-listener-tty.sh"
	assert_failure
}
