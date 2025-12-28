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
	print(f"controller_listener_kiosk_mode: {msg}", flush=True)


def cover_path(path_id: str) -> None:
	if os.environ.get("KIOSK_RETROPIE_PATH_COVERAGE", "0") != "1":
		return
	# Prefer suite-wide append file when present.
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
	by_id_dir = os.environ.get("RETROPIE_INPUT_BY_ID_DIR") or os.environ.get("KIOSK_RETROPIE_INPUT_BY_ID_DIR") or "/dev/input/by-id"
	by_id = glob.glob(os.path.join(by_id_dir, "*event-joystick"))
	if not by_id:
		by_id = glob.glob(os.path.join(by_id_dir, "*joystick"))
	paths: list[str] = []
	for p in sorted(set(by_id)):
		try:
			rp = os.path.realpath(p)
			if os.path.basename(rp).startswith("event"):
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
	combo_window_sec = float(os.environ.get("RETROPIE_COMBO_WINDOW_SEC") or os.environ.get("KIOSK_RETROPIE_COMBO_WINDOW_SEC") or "0.75")
	debounce_sec = float(os.environ.get("RETROPIE_ACTION_DEBOUNCE_SEC") or "1.0")
	max_triggers = int(os.environ.get("RETROPIE_MAX_TRIGGERS") or os.environ.get("KIOSK_RETROPIE_MAX_TRIGGERS") or "0")
	max_loops = int(os.environ.get("RETROPIE_MAX_LOOPS") or os.environ.get("KIOSK_RETROPIE_MAX_LOOPS") or "0")
	last_fire = 0.0
	pressed: set[int] = set()
	press_times: dict[int, float] = {}
	enter_combo_armed = True
	triggers = 0
	loops = 0

	# Safety: only run behavior if kiosk is up.
	if not is_active("kiosk.service"):
		cover_path("controller-kiosk:kiosk-not-active")
		log("kiosk.service not active; exiting")
		return 0

	sel = selectors.DefaultSelector()
	fmt = "llHHi"
	size = struct.calcsize(fmt)

	opened = False
	for dev in devices():
		try:
			fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
		except OSError as e:
			cover_path("controller-kiosk:device-open-failed")
			log(f"Unable to open {dev}: {e}")
			continue
		sel.register(fd, selectors.EVENT_READ, data=dev)
		cover_path("controller-kiosk:listening")
		log(f"Listening on {dev}")
		opened = True

	if not opened:
		cover_path("controller-kiosk:no-devices")
		log("No controller devices found")
		return 1

	while True:
		loops += 1
		if max_loops and loops > max_loops:
			return 0

		# If kiosk mode ended, stop this listener.
		if not is_active("kiosk.service"):
			log("kiosk.service stopped; exiting")
			return 0

		for key, _mask in sel.select(timeout=1.0):
			fd = key.fileobj
			try:
				data = os.read(fd, size * 16)
			except OSError:
				continue

			# EOF (e.g. FIFO writer closed): avoid a tight loop where the fd stays readable.
			if not data:
				time.sleep(0.05)
				continue

			for off in range(0, len(data) - (len(data) % size), size):
				_sec, _usec, etype, code, value = struct.unpack_from(fmt, data, off)
				if etype != 1:
					continue

				# Only track press/release; ignore auto-repeat.
				if value not in (0, 1):
					continue

				now = time.time()
				if value == 1:
					pressed.add(code)
					press_times.setdefault(code, now)
				else:
					pressed.discard(code)
					press_times.pop(code, None)
					if enter_sequence_codes and not all(c in pressed for c in enter_sequence_codes):
						enter_combo_armed = True
					continue

				if not enter_sequence_codes:
					continue

				if not all(c in pressed for c in enter_sequence_codes):
					continue

				times = [press_times.get(c, now) for c in enter_sequence_codes]
				if (max(times) - min(times)) > combo_window_sec:
					continue

				# Debounce actions.
				if not enter_combo_armed or (now - last_fire) < debounce_sec:
					continue
				enter_combo_armed = False
				last_fire = now

				if is_active("retro-mode.service"):
					continue

				log("Enter combo matched -> switching to RetroPie mode")
				cover_path("controller-kiosk:trigger-start-retro")
				systemctl("start", "retro-mode.service")
				triggers += 1
				if max_triggers and triggers >= max_triggers:
					return 0


if __name__ == "__main__":
	raise SystemExit(main())
PY
