#!/usr/bin/env bash
set -euo pipefail

# Print controller button codes from Linux evdev.
#
# Usage:
#   sudo /usr/local/bin/retro-ha-controller-codes.sh
#   # or from repo:
#   sudo ./scripts/input/controller-codes.sh
#
# It listens on /dev/input/by-id/*event-joystick by default.
# Override directory for testing:
#   RETRO_HA_INPUT_BY_ID_DIR=/some/dir sudo ./scripts/input/controller-codes.sh

exec python3 - << 'PY'
import glob
import os
import selectors
import struct
import time


def log(msg: str) -> None:
    print(f"controller_codes: {msg}", flush=True)


def devices() -> list[str]:
    by_id_dir = os.environ.get("RETRO_HA_INPUT_BY_ID_DIR", "/dev/input/by-id")
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
    sel = selectors.DefaultSelector()
    fmt = "llHHi"  # timeval(sec,usec), type, code, value
    size = struct.calcsize(fmt)

    opened = False
    for dev in devices():
        try:
            fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as e:
            log(f"Unable to open {dev}: {e}")
            continue
        sel.register(fd, selectors.EVENT_READ, data=dev)
        log(f"Listening on {dev} (press buttons; Ctrl+C to quit)")
        opened = True

    if not opened:
        log("No controller devices found under /dev/input/by-id/*joystick")
        return 1

    while True:
        for key, _mask in sel.select(timeout=1.0):
            fd = key.fileobj
            dev = key.data
            try:
                data = os.read(fd, size * 32)
            except OSError:
                continue

            for off in range(0, len(data) - (len(data) % size), size):
                sec, usec, etype, code, value = struct.unpack_from(fmt, data, off)
                # etype=1 => EV_KEY. value=1 press, 0 release, 2 repeat.
                if etype == 1 and value in (0, 1, 2):
                    t = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(sec))
                    v = {0: "release", 1: "press", 2: "repeat"}.get(value, str(value))
                    print(f"{t}.{usec:06d} dev={dev} type=EV_KEY code={code} value={v}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
PY
