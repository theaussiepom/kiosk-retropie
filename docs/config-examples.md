# Configuration examples

This project is configured via `/etc/retro-ha/config.env`.

These examples are intentionally verbose and scenario-driven. Copy one, then delete what you don’t need.

Notes:

- `RETRO_HA_REPO_URL` + `RETRO_HA_REPO_REF` are required for first-boot installs (cloud-init bootstrap).
- `HA_URL` is required for kiosk mode.
- A line like `FOO=` means “set but empty” (often used to intentionally disable a feature or trigger a specific branch).

---

## 1) Minimal: HA kiosk + manual Retro

Use this when you only want the core appliance behavior and will switch modes manually.

```bash
# Required: bootstrap pin
RETRO_HA_REPO_URL=https://github.com/theaussiepom/retro-ha-appliance.git
RETRO_HA_REPO_REF=v0.0.0

# Required: kiosk
HA_URL=http://homeassistant.local:8123/lovelace/0

# Optional display tweaks
RETRO_HA_SCREEN_ROTATION=normal
RETRO_HA_X_VT=7
RETRO_HA_RETRO_X_VT=8

# Keep optional integrations off
RETRO_HA_LED_MQTT_ENABLED=0
RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=0
RETRO_HA_SAVE_BACKUP_ENABLED=0
```

---

## 2) “Appliance” pinning: use a commit SHA

This maximizes repeatability: every Pi installs the same code.

```bash
RETRO_HA_REPO_URL=https://github.com/theaussiepom/retro-ha-appliance.git
RETRO_HA_REPO_REF=863329f

HA_URL=http://homeassistant.local:8123/dashboard-retro-kiosk
```

---

## 3) Rotate screen left + custom Chromium profile

Useful for portrait displays or odd mounting.

```bash
RETRO_HA_REPO_URL=https://github.com/theaussiepom/retro-ha-appliance.git
RETRO_HA_REPO_REF=v0.0.0

HA_URL=http://homeassistant.local:8123/lovelace/retro

RETRO_HA_SCREEN_ROTATION=left
RETRO_HA_CHROMIUM_PROFILE_DIR=/var/lib/retro-ha/chromium-profile
```

---

## 4) Controller switching: custom Start button key code

If your controller reports a different key code than the default (`315`).

```bash
RETRO_HA_REPO_URL=https://github.com/theaussiepom/retro-ha-appliance.git
RETRO_HA_REPO_REF=v0.0.0

HA_URL=http://homeassistant.local:8123/lovelace/retro

RETRO_HA_START_BUTTON_CODE=314
RETRO_HA_START_DEBOUNCE_SEC=0.5
```

---

## 5) ROM sync from NFS (read-only)

This syncs ROMs *into* local storage at boot. Gameplay does not run from NFS.

```bash
RETRO_HA_REPO_URL=https://github.com/theaussiepom/retro-ha-appliance.git
RETRO_HA_REPO_REF=v0.0.0

HA_URL=http://homeassistant.local:8123/lovelace/retro

# Enable NFS ROM sync
NFS_SERVER=192.168.1.20
NFS_PATH=/export/retropie

# Optional: mount point and subdir
RETRO_HA_NFS_MOUNT_POINT=/mnt/retro-ha-roms
RETRO_HA_NFS_ROMS_SUBDIR=roms

# Optional: only sync some systems
RETRO_HA_ROMS_SYSTEMS=nes,snes,megadrive
RETRO_HA_ROMS_EXCLUDE_SYSTEMS=

# Optional: mirror deletions (dangerous if you’re not expecting it)
RETRO_HA_ROMS_SYNC_DELETE=0
```

---

## 6) Save backups to NFS (read-write, periodic)

This copies local saves/states to NFS on a timer and skips while Retro mode is active.

```bash
RETRO_HA_REPO_URL=https://github.com/theaussiepom/retro-ha-appliance.git
RETRO_HA_REPO_REF=v0.0.0

HA_URL=http://homeassistant.local:8123/lovelace/retro

RETRO_HA_SAVE_BACKUP_ENABLED=1

# Defaults to NFS_SERVER/NFS_PATH if unset
RETRO_HA_SAVE_BACKUP_NFS_SERVER=192.168.1.20
RETRO_HA_SAVE_BACKUP_NFS_PATH=/export/retro-ha-backups

# Where to mount the backup share
RETRO_HA_SAVE_BACKUP_DIR=/mnt/retro-ha-backup

# Subdir on the mounted share
RETRO_HA_SAVE_BACKUP_SUBDIR=pi-living-room

# Mirror deletions from local -> NFS
RETRO_HA_SAVE_BACKUP_DELETE=0
```

---

## 7) Home Assistant integration: MQTT LED control

Enables two-way LED sync: commands from HA control sysfs LEDs, and sysfs changes publish state.

```bash
RETRO_HA_REPO_URL=https://github.com/theaussiepom/retro-ha-appliance.git
RETRO_HA_REPO_REF=v0.0.0

HA_URL=http://homeassistant.local:8123/lovelace/retro

RETRO_HA_LED_MQTT_ENABLED=1
RETRO_HA_MQTT_TOPIC_PREFIX=retro-ha
RETRO_HA_LED_MQTT_POLL_SEC=2

MQTT_HOST=192.168.1.50
MQTT_PORT=1883
MQTT_USERNAME=homeassistant
MQTT_PASSWORD=replace-me
MQTT_TLS=0
```

---

## 8) Home Assistant integration: MQTT screen brightness

Publishes brightness state and accepts brightness percent commands.

```bash
RETRO_HA_REPO_URL=https://github.com/theaussiepom/retro-ha-appliance.git
RETRO_HA_REPO_REF=v0.0.0

HA_URL=http://homeassistant.local:8123/lovelace/retro

RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1
RETRO_HA_MQTT_TOPIC_PREFIX=retro-ha
RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=2

# Optional: pick a specific backlight device (otherwise auto-detect)
RETRO_HA_BACKLIGHT_NAME=rpi_backlight

MQTT_HOST=192.168.1.50
MQTT_PORT=1883
MQTT_USERNAME=homeassistant
MQTT_PASSWORD=replace-me
MQTT_TLS=0
```

---

## 9) MQTT over TLS (typical pattern)

If your broker requires TLS, you’ll also need the broker CA available on the Pi.

```bash
RETRO_HA_REPO_URL=https://github.com/theaussiepom/retro-ha-appliance.git
RETRO_HA_REPO_REF=v0.0.0

HA_URL=http://homeassistant.local:8123/lovelace/retro

RETRO_HA_LED_MQTT_ENABLED=1
RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1
RETRO_HA_MQTT_TOPIC_PREFIX=retro-ha

MQTT_HOST=mqtt.example.internal
MQTT_PORT=8883
MQTT_USERNAME=homeassistant
MQTT_PASSWORD=replace-me
MQTT_TLS=1

# If the scripts support it in your setup, you may also mount a CA file and/or use mosquitto client options.
# (Broker TLS options vary; keep this file focused on env-vars the appliance consumes.)
```
