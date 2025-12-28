# Glossary

Short definitions for terms used across the docs.

## Appliance concepts

- **Mode**: One of the mutually-exclusive runtime states on the Pi: kiosk mode or Retro mode.
- **Fail-open**: A non-fatal failure mode: if something external is unavailable (for example NFS or kiosk mode),
  the appliance continues operating using local data where possible.

## Storage + NFS

- **NFS**: Network File System; used here for optional ROM sync (NFS -> local) and optional save backups (local -> NFS).
- **Share layout**: The expected directories at the NFS export root: `roms/` and `backups/`.
- **Hostname component**: The per-device directory under `backups/<hostname>/` used to keep multiple kiosks separated.

## Linux + systemd

- **systemd**: The Linux init/service manager. Starts services at boot, restarts them on failure, and enforces ordering.
- **Unit**: A systemd configuration file that describes something systemd manages (e.g. `.service`, `.timer`).
- **Service**: A unit (`.service`) describing how to run a process (ExecStart, user, restart policy, dependencies).
- **Timer**: A unit (`.timer`) that triggers a service on a schedule.
- **OnFailure**: A systemd directive that starts another unit if the current one fails.
- **journald**: The system logging daemon used by systemd.
- **journalctl**: The command used to read logs from journald.

## Display/session plumbing

- **Xorg**: The X display server used here to render Chromium and RetroPie.
- **xinit**: A helper that starts an X server + a program/script (used to launch the kiosk/retro session).
- **VT (virtual terminal)**: Linux text consoles (e.g. VT7/VT8). This project uses fixed VTs to keep modes
  isolated.
- **logind**: The systemd component that manages user sessions and device access (seat ownership, input, display).

## Hardware interfaces

- **evdev**: Linux’s standard input event interface. Controllers appear as `/dev/input/event*` devices.
- **sysfs**: Kernel-exposed files under `/sys/` used to control hardware (LED triggers, backlight brightness, etc).
- **Backlight**: The sysfs interface under `/sys/class/backlight/<name>/` used to read/write screen brightness.

## MQTT

- **MQTT**: A lightweight pub/sub messaging protocol commonly used by dashboards/controllers and IoT devices.
- **Topic**: The string namespace messages are published to (e.g. `kiosk-retropie/led/act/set`).
- **Topic prefix**: A shared prefix (`KIOSK_MQTT_TOPIC_PREFIX`, default `kiosk-retropie`) so related topics group
  together.
- **Retained message**: A message stored by the broker and delivered immediately to new subscribers (useful for
  “current state”).
- **State topic**: A topic where the appliance publishes current state for UIs/automation.
- **Set/command topic**: A topic where a dashboard/controller (or another client) publishes desired state.

## Repo tooling

- **Devcontainer**: A Docker image + configuration used to provide a consistent toolchain for development and CI.
- **Bats (Bash Automated Testing System)**: The test framework used for Bash scripts.
- **kcov**: Coverage tool used here to measure Bash line coverage and enforce 100% coverage in CI.
