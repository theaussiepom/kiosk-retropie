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
	if os.environ.get("RETRO_HA_PATH_COVERAGE", "0") != "1":
		return
	path_file = os.environ.get("RETRO_HA_CALLS_FILE_APPEND") or os.environ.get("RETRO_HA_CALLS_FILE")
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
	explicit = os.environ.get("RETRO_HA_INPUT_DEVICES", "").strip()
	if explicit:
		paths: list[str] = []
		for token in [t for t in explicit.replace(",", ":").split(":") if t.strip()]:
			p = token.strip()
			paths.append(p)
		return paths

	# Prefer event devices for consistent key codes.
	by_id_dir = os.environ.get("RETRO_HA_INPUT_BY_ID_DIR", "/dev/input/by-id")
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
	# Backwards-compatible fallbacks:
	# - RETRO_HA_START_BUTTON_CODE (legacy enter/exit trigger)
	# - RETRO_HA_A_BUTTON_CODE (legacy exit combo second button)
	enter_trigger_code = int(
		os.environ.get(
			"RETRO_HA_RETRO_ENTER_TRIGGER_CODE",
			os.environ.get("RETRO_HA_START_BUTTON_CODE", "315"),
		)
	)
	exit_trigger_code = int(
		os.environ.get(
			"RETRO_HA_RETRO_EXIT_TRIGGER_CODE",
			os.environ.get("RETRO_HA_START_BUTTON_CODE", "315"),
		)
	)
	exit_second_code = int(
		os.environ.get(
			"RETRO_HA_RETRO_EXIT_SECOND_CODE",
			os.environ.get("RETRO_HA_A_BUTTON_CODE", "304"),
		)
	)
	combo_window_sec = float(os.environ.get("RETRO_HA_COMBO_WINDOW_SEC", "0.75"))
	debounce_sec = float(os.environ.get("RETRO_HA_START_DEBOUNCE_SEC", "1.0"))
	max_triggers = int(os.environ.get("RETRO_HA_MAX_TRIGGERS", "0"))
	max_loops = int(os.environ.get("RETRO_HA_MAX_LOOPS", "0"))
	last_fire = 0.0
	last_start = 0.0
	last_a = 0.0
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
					if code == exit_second_code:
						last_a = now
					elif code == enter_trigger_code or code == exit_trigger_code:
						last_start = now

						# Debounce only the START button triggers.
						if now - last_fire < debounce_sec:
							continue
						last_fire = now

						retro_active = is_active("retro-mode.service")

						# Combo behavior: Exit trigger + exit second while Retro is active returns to HA.
						# We treat the combo as: (A pressed within window) AND Retro active.
						if retro_active and code == exit_trigger_code and (now - last_a) <= combo_window_sec:
							log("Exit combo pressed -> returning to HA kiosk mode")
							cover_path("controller-tty:trigger-stop-retro")
							systemctl("stop", "retro-mode.service")
							cover_path("controller-tty:trigger-start-ha")
							systemctl("start", "ha-kiosk.service")
							triggers += 1
							if max_triggers and triggers >= max_triggers:
								return 0
							continue

						# Default behavior: Start enters Retro when not already active.
						if retro_active:
							continue

						# Only enter Retro when the *enter* trigger is pressed.
						if code != enter_trigger_code:
							continue

						log("Enter Retro trigger pressed -> entering RetroPie mode")
						# Stop HA kiosk first; Conflicts also enforces this.
						cover_path("controller-tty:trigger-stop-ha")
						systemctl("stop", "ha-kiosk.service")
						cover_path("controller-tty:trigger-start-retro")
						systemctl("start", "retro-mode.service")
						triggers += 1
						if max_triggers and triggers >= max_triggers:
							return 0


if __name__ == "__main__":
	raise SystemExit(main())
PY
