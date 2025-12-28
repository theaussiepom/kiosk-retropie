import fcntl
import os
import struct
import sys
import time

fifo_path = sys.argv[1]
ready_file = sys.argv[2]

UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN = 0x00
EV_KEY = 0x01
SYN_REPORT = 0


def ioctl(fd, req, arg):
    fcntl.ioctl(fd, req, arg)


def write_event(fd, etype, code, value):
    sec = int(time.time())
    usec = 0
    # timeval: long, long; type: ushort; code: ushort; value: int
    fd.write(struct.pack("llHHi", sec, usec, etype, code, value))


u = open("/dev/uinput", "wb+", buffering=0)

# Enable key + syn.
ioctl(u, UI_SET_EVBIT, EV_KEY)
ioctl(u, UI_SET_EVBIT, EV_SYN)

# Enable a small key set we use in tests.
for code in (304, 315):
    ioctl(u, UI_SET_KEYBIT, code)

name = b"kiosk-retropie-uinput"
name_padded = name + b"\x00" * (80 - len(name))

bustype = 0x03  # BUS_USB
vendor = 0x1234
product = 0x5678
version = 1

# Pack uinput_user_dev.
# Layout size: 80s + 4H + i + 64i*4 = 1116 bytes
user_dev = bytearray(1116)
struct.pack_into("80sHHHHi", user_dev, 0, name_padded, bustype, vendor, product, version, 0)
u.write(user_dev)

fcntl.ioctl(u, UI_DEV_CREATE)

os.makedirs(os.path.dirname(ready_file), exist_ok=True)
with open(ready_file, "w", encoding="utf-8") as f:
    f.write("ready\n")

with open(fifo_path, "r", encoding="utf-8") as fifo:
    for line in fifo:
        line = line.strip()
        if not line:
            continue
        codes = [int(tok) for tok in line.replace(",", " ").split() if tok.strip()]

        # Press all, then release all after a short hold.
        for c in codes:
            write_event(u, EV_KEY, c, 1)
        write_event(u, EV_SYN, SYN_REPORT, 0)
        time.sleep(0.2)
        for c in codes:
            write_event(u, EV_KEY, c, 0)
        write_event(u, EV_SYN, SYN_REPORT, 0)

fcntl.ioctl(u, UI_DEV_DESTROY)
u.close()
