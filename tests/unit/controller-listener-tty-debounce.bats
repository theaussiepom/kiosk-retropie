#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root

	# Deterministic behavior: allow us to hold buttons and test debounce.
	export RETROPIE_ACTION_DEBOUNCE_SEC=1.0
	export RETROPIE_COMBO_WINDOW_SEC=10.0
	# Keep the listener alive even if one trigger happens.
	export RETROPIE_MAX_TRIGGERS=2
	# Safety: avoid infinite loops if something goes wrong.
	export RETROPIE_MAX_LOOPS=500

	# Use a state file so the stub systemctl can track active units.
	export SYSTEMCTL_STATE_FILE="$TEST_ROOT/systemctl.state"
	printf '%s\n' ":kiosk.service:" >"$SYSTEMCTL_STATE_FILE"

	make_fake_controller_fifo
}

teardown() {
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

	local fifo="$TEST_ROOT/dev/input/event0"
	mkfifo "$fifo"

	# Name must match *event-joystick glob in the production scripts.
	ln -s "$fifo" "$by_id_dir/fake-event-joystick"

	export RETROPIE_INPUT_BY_ID_DIR="$by_id_dir"
	export FAKE_CONTROLLER_FIFO="$fifo"
}

emit_press() {
	local fifo_path="$1"
	local code="$2"

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

end = time.time() + 10.0
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

emit_two_presses() {
	local fifo_path="$1"
	local code1="$2"
	local code2="$3"

	python3 - "$fifo_path" "$code1" "$code2" <<'PY'
import errno
import os
import struct
import sys
import time

fifo_path = sys.argv[1]
code1 = int(sys.argv[2])
code2 = int(sys.argv[3])

fmt = "llHHi"  # must match listener scripts

def payload(code: int) -> bytes:
	sec = int(time.time())
	usec = 0
	etype = 1
	value = 1
	return struct.pack(fmt, sec, usec, etype, code, value)

end = time.time() + 10.0
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
	os.write(fd, payload(code1))
	time.sleep(0.05)
	os.write(fd, payload(code2))
finally:
	os.close(fd)
PY
}

assert_calls_contains() {
	local needle="$1"
	local expected="$needle"
	# systemctl stub logs with: printf 'systemctl %q\n' "$*"
	# which escapes spaces in the argument string.
	if [[ "$expected" == systemctl\ * ]]; then
		local arg_str="${expected#systemctl }"
		expected="systemctl $(printf '%q' "$arg_str")"
	fi
	assert_file_contains "$KIOSK_RETROPIE_CALLS_FILE" "$expected"
}

@test "controller-listener-tty: debounced exit combo requires release before retrigger" {
	listener_log="$TEST_ROOT/listener.log"

	# Start listener in background.
	bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/input/controller-listener-tty.sh" >"$listener_log" 2>&1 &
	LISTENER_PID=$!

	# 1) Trigger enter (kiosk -> retro). This sets last_fire.
	emit_press "$FAKE_CONTROLLER_FIFO" 315
	sleep 0.1

	assert_calls_contains "systemctl stop kiosk.service"
	assert_calls_contains "systemctl start retro-mode.service"

	# 2) Immediately attempt exit combo within debounce (Start+A). Hold buttons (no releases).
	emit_two_presses "$FAKE_CONTROLLER_FIFO" 315 304

	# 3) After debounce passes, send an unrelated press while buttons are still held.
	# Without the fix, this could trigger exit without a fresh combo.
	sleep 1.1
	emit_press "$FAKE_CONTROLLER_FIFO" 999
	sleep 0.1

	# Should NOT have triggered exit (retro -> kiosk).
	run grep -F "systemctl $(printf '%q' 'stop retro-mode.service')" "$KIOSK_RETROPIE_CALLS_FILE"
	assert_failure
	run grep -F "systemctl $(printf '%q' 'start kiosk.service')" "$KIOSK_RETROPIE_CALLS_FILE"
	assert_failure
}
