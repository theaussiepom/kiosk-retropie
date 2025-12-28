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
	enter_sequence_raw = (
		os.environ.get("RETROPIE_ENTER_SEQUENCE_CODES")
		or os.environ.get("KIOSK_RETROPIE_RETRO_ENTER_SEQUENCE_CODES")
		or ""
	).strip()
	if enter_sequence_raw:
		enter_sequence_codes = [int(tok.strip()) for tok in enter_sequence_raw.split(",") if tok.strip()]
	else:
		enter_sequence_codes = [enter_trigger_code]
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
	debounce_sec = float(os.environ.get("RETROPIE_ACTION_DEBOUNCE_SEC") or "1.0")
	max_triggers = int(os.environ.get("RETROPIE_MAX_TRIGGERS") or os.environ.get("KIOSK_RETROPIE_MAX_TRIGGERS") or "0")
	max_loops = int(os.environ.get("RETROPIE_MAX_LOOPS") or os.environ.get("KIOSK_RETROPIE_MAX_LOOPS") or "0")
	last_fire = 0.0
	last_start = 0.0
	pressed: set[int] = set()
	press_times: dict[int, float] = {}
	enter_combo_armed = True
	exit_combo_armed = True
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

			# EOF (e.g. FIFO writer closed): avoid a tight loop where the fd stays readable.
			# This also lets tests reconnect a writer to emit the next event.
			if not data:
				time.sleep(0.05)
				continue

			# Process in chunks.
			for off in range(0, len(data) - (len(data) % size), size):
				_sec, _usec, etype, code, value = struct.unpack_from(fmt, data, off)
				if etype != 1:
					continue

				# Only track press/release; ignore auto-repeat.
				if value not in (0, 1):
					continue

				now = time.time()
				last_start = now

				if value == 1:
					pressed.add(code)
					press_times.setdefault(code, now)
				else:
					pressed.discard(code)
					press_times.pop(code, None)
					if enter_sequence_codes and not all(c in pressed for c in enter_sequence_codes):
						enter_combo_armed = True
					if exit_sequence_codes and not all(c in pressed for c in exit_sequence_codes):
						exit_combo_armed = True
					continue

				retro_active = is_active("retro-mode.service")

				# Exit combo behavior: when Retro is active, require the configured buttons
				# to be pressed *together* (held simultaneously). Order doesn't matter.
				# combo_window_sec defines the max allowed time between first and last press.
				if retro_active and exit_sequence_codes:
					if all(c in pressed for c in exit_sequence_codes):
						times = [press_times.get(c, now) for c in exit_sequence_codes]
						if (max(times) - min(times)) <= combo_window_sec:
							# Important: even if we are debounced, consume this match so holding
							# the buttons cannot auto-trigger later without a release.
							if exit_combo_armed:
								exit_combo_armed = False
								if (now - last_fire) >= debounce_sec:
									last_fire = now
									log("Exit combo matched -> returning to kiosk mode")
									cover_path("controller-tty:trigger-stop-retro")
									systemctl("stop", "retro-mode.service")
									cover_path("controller-tty:trigger-start-kiosk")
									systemctl("start", "kiosk.service")
									triggers += 1
									if max_triggers and triggers >= max_triggers:
										return 0
					continue

				# Default behavior: Enter Retro when not already active.
				if retro_active:
					continue

				if enter_sequence_codes and all(c in pressed for c in enter_sequence_codes):
					times = [press_times.get(c, now) for c in enter_sequence_codes]
					if (max(times) - min(times)) <= combo_window_sec:
						# Important: even if we are debounced, consume this match so holding
						# the buttons cannot auto-trigger later without a release.
						if enter_combo_armed:
							enter_combo_armed = False
							if (now - last_fire) >= debounce_sec:
								last_fire = now

								log("Enter combo matched -> entering RetroPie mode")
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
