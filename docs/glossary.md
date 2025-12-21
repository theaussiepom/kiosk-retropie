# Glossary

Short definitions for terms used across the docs.

## Appliance concepts

- **Mode**: One of the mutually-exclusive runtime states on the Pi: HA kiosk mode or Retro mode.
- **Fail-open**: If kiosk mode is unhealthy/unavailable, the system should still make Retro mode reachable.
- **Repo pinning**: Installing from a specific branch/tag/commit via `RETRO_HA_REPO_URL` + `RETRO_HA_REPO_REF`.

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

## MQTT

- **MQTT**: A lightweight pub/sub messaging protocol commonly used by Home Assistant and IoT devices.
- **Topic**: The string namespace messages are published to (e.g. `retro-ha/led/act/set`).
- **Topic prefix**: A shared prefix (`RETRO_HA_MQTT_TOPIC_PREFIX`, default `retro-ha`) so related topics group
  together.
- **Retained message**: A message stored by the broker and delivered immediately to new subscribers (useful for
  “current state”).
- **State topic**: A topic where the appliance publishes current state for UIs/automation.
- **Set/command topic**: A topic where Home Assistant (or another client) publishes desired state.

## Repo tooling

- **Devcontainer**: A Docker image + configuration used to provide a consistent toolchain for development and CI.
- **Bats (Bash Automated Testing System)**: The test framework used for Bash scripts.
- **kcov**: Coverage tool used here to measure Bash line coverage and enforce 100% coverage in CI.
