#!/usr/bin/env bash
set -euo pipefail

exec python3 - << 'PY'
import glob
import os
import selectors
import struct
import subprocess
import time


def log(msg: str) -> None:
	print(f"controller_listener_tty: {msg}", flush=True)


def cover_path(path_id: str) -> None:
	if os.environ.get("KIOSK_RETROPIE_PATH_COVERAGE", "0") != "1":
		return
	path_file = os.environ.get("KIOSK_RETROPIE_CALLS_FILE_APPEND") or os.environ.get("KIOSK_RETROPIE_CALLS_FILE")
	if not path_file:
		return
	try:
		os.makedirs(os.path.dirname(path_file), exist_ok=True)
	except Exception:
		pass
	try:
		with open(path_file, "a", encoding="utf-8") as f:
			f.write(f"PATH {path_id}\n")
	except Exception:
		pass


def systemctl(*args: str) -> int:
	return subprocess.call(["systemctl", *args])


def is_active(unit: str) -> bool:
	return subprocess.call(["systemctl", "is-active", "--quiet", unit]) == 0


def devices() -> list[str]:
	# Test injection: allow explicit device list (paths) to avoid relying on real /dev/input.
	# Format: colon/comma/space-separated list.
	explicit = os.environ.get("RETROPIE_INPUT_DEVICES") or os.environ.get("KIOSK_RETROPIE_INPUT_DEVICES", "")
	explicit = explicit.strip()
	if explicit:
		paths: list[str] = []
		for token in [t for t in explicit.replace(",", ":").split(":") if t.strip()]:
			p = token.strip()
			paths.append(p)
		return paths

	# Prefer event devices for consistent key codes.
	by_id_dir = os.environ.get("RETROPIE_INPUT_BY_ID_DIR") or os.environ.get("KIOSK_RETROPIE_INPUT_BY_ID_DIR") or "/dev/input/by-id"
	by_id = glob.glob(os.path.join(by_id_dir, "*event-joystick"))
	if not by_id:
		by_id = glob.glob(os.path.join(by_id_dir, "*joystick"))
	paths: list[str] = []
	for p in sorted(set(by_id)):
		try:
			rp = os.path.realpath(p)
			# Only evdev event devices match the input_event struct.
			if os.path.basename(rp).startswith("event"):
				# Open the /dev/input/by-id symlink (not eventX) to avoid hardcoding.
				paths.append(p)
			else:
				log(f"Ignoring non-evdev joystick device: {p} -> {rp}")
		except OSError:
			continue
	return paths


def main() -> int:
	# Configurable controller codes.
	enter_trigger_code = int(os.environ.get("RETROPIE_ENTER_TRIGGER_CODE") or os.environ.get("KIOSK_RETROPIE_RETRO_ENTER_TRIGGER_CODE") or "315")
	legacy_exit_trigger_code = int(os.environ.get("RETROPIE_EXIT_TRIGGER_CODE") or os.environ.get("KIOSK_RETROPIE_RETRO_EXIT_TRIGGER_CODE") or "315")
	legacy_exit_second_code = int(os.environ.get("RETROPIE_EXIT_SECOND_CODE") or os.environ.get("KIOSK_RETROPIE_RETRO_EXIT_SECOND_CODE") or "304")
	exit_sequence_raw = (
		os.environ.get("RETROPIE_EXIT_SEQUENCE_CODES")
		or os.environ.get("KIOSK_RETROPIE_RETRO_EXIT_SEQUENCE_CODES")
		or ""
	).strip()
	if exit_sequence_raw:
		exit_sequence_codes = [int(tok.strip()) for tok in exit_sequence_raw.split(",") if tok.strip()]
	else:
		exit_sequence_codes = [legacy_exit_trigger_code, legacy_exit_second_code]
	combo_window_sec = float(os.environ.get("RETROPIE_COMBO_WINDOW_SEC") or os.environ.get("KIOSK_RETROPIE_COMBO_WINDOW_SEC") or "0.75")
	debounce_sec = float(os.environ.get("RETROPIE_START_DEBOUNCE_SEC") or os.environ.get("KIOSK_RETROPIE_START_DEBOUNCE_SEC") or "1.0")
	max_triggers = int(os.environ.get("RETROPIE_MAX_TRIGGERS") or os.environ.get("KIOSK_RETROPIE_MAX_TRIGGERS") or "0")
	max_loops = int(os.environ.get("RETROPIE_MAX_LOOPS") or os.environ.get("KIOSK_RETROPIE_MAX_LOOPS") or "0")
	last_fire = 0.0
	last_start = 0.0
	exit_seq_start = 0.0
	exit_seq_index = 0
	triggers = 0
	loops = 0

	sel = selectors.DefaultSelector()
	fmt = "llHHi"  # timeval(sec,usec), type, code, value (native long size)
	size = struct.calcsize(fmt)

	opened = False
	for dev in devices():
		try:
			fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
		except OSError as e:
			cover_path("controller-tty:device-open-failed")
			log(f"Unable to open {dev}: {e}")
			continue
		sel.register(fd, selectors.EVENT_READ, data=dev)
		cover_path("controller-tty:listening")
		log(f"Listening on {dev}")
		opened = True

	if not opened:
		cover_path("controller-tty:no-devices")
		log("No controller devices found under /dev/input/by-id/*joystick")
		return 1

	while True:
		loops += 1
		if max_loops and loops > max_loops:
			return 0

		for key, _mask in sel.select(timeout=1.0):
			fd = key.fileobj
			try:
				data = os.read(fd, size * 16)
			except OSError:
				continue

			# Process in chunks.
			for off in range(0, len(data) - (len(data) % size), size):
				_sec, _usec, etype, code, value = struct.unpack_from(fmt, data, off)
				if etype == 1 and value == 1:
					now = time.time()
					last_start = now

					retro_active = is_active("retro-mode.service")

					# Exit sequence behavior: when Retro is active, require the full sequence
					# of button codes within combo_window_sec.
					if retro_active and exit_sequence_codes:
						# Reset on timeout.
						if exit_seq_index and (now - exit_seq_start) > combo_window_sec:
							exit_seq_index = 0

						# Start / continue a matching sequence.
						if exit_seq_index == 0:
							if code == exit_sequence_codes[0]:
								exit_seq_start = now
								exit_seq_index = 1
						else:
							if code == exit_sequence_codes[exit_seq_index]:
								exit_seq_index += 1
							else:
								# Wrong code resets; allow current code to restart.
								exit_seq_index = 1 if code == exit_sequence_codes[0] else 0
								exit_seq_start = now if exit_seq_index else 0.0

						if exit_seq_index == len(exit_sequence_codes):
							# Debounce actions (not individual presses).
							if now - last_fire >= debounce_sec:
								last_fire = now
								log("Exit sequence matched -> returning to kiosk mode")
								cover_path("controller-tty:trigger-stop-retro")
								systemctl("stop", "retro-mode.service")
								cover_path("controller-tty:trigger-start-kiosk")
								systemctl("start", "kiosk.service")
								triggers += 1
								exit_seq_index = 0
								exit_seq_start = 0.0
								if max_triggers and triggers >= max_triggers:
									return 0
							continue

					# Default behavior: Enter Retro when not already active.
					if retro_active:
						continue

					# Only enter Retro when the *enter* trigger is pressed.
					if code != enter_trigger_code:
						continue

					# Debounce actions.
					if now - last_fire < debounce_sec:
						continue
					last_fire = now

					log("Enter Retro trigger pressed -> entering RetroPie mode")
					# Stop kiosk first; Conflicts also enforces this.
					cover_path("controller-tty:trigger-stop-kiosk")
					systemctl("stop", "kiosk.service")
					cover_path("controller-tty:trigger-start-retro")
					systemctl("start", "retro-mode.service")
					triggers += 1
					if max_triggers and triggers >= max_triggers:
						return 0


if __name__ == "__main__":
	raise SystemExit(main())
PY
