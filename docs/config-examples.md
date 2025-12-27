# Configuration examples

This project is configured via `/etc/kiosk-retropie/config.env`.

This repo provides two canonical examples:

1) Manual install (config file only): [examples/config.env](../examples/config.env)
2) Flashing install (Pi Imager / cloud-init): [cloud-init/user-data.example.yml](../cloud-init/user-data.example.yml)

Notes:

- A line like `FOO=` means “set but empty”. This is often used to intentionally disable a feature or to force a
  script down a specific error-handling path.
- Some variables are “obvious plumbing” (e.g. `NFS_SERVER`), while others are application-specific (e.g.
  `KIOSK_MQTT_TOPIC_PREFIX`). The examples include inline comments for the application-specific ones.

## Manual install example

The manual install path assumes you can SSH in and run the installer yourself.

How to use it:

1. Copy it into place:

  ```bash
  sudo mkdir -p /etc/kiosk-retropie
  sudo cp /opt/kiosk-retropie/examples/config.env /etc/kiosk-retropie/config.env
  ```

1. Edit `/etc/kiosk-retropie/config.env` and fill in at least `KIOSK_URL`.
1. Run the installer:

  ```bash
  sudo /opt/kiosk-retropie/scripts/install.sh
  ```

The installer creates the `retropi` user (if needed) and installs systemd services that run under that account.

Mandatory variables for this scenario:

- `KIOSK_URL`
- `NFS_SERVER`

Notes:

- NFS config is mandatory, but runtime behavior is fail-open: if NFS is unreachable, the appliance keeps running
  using local storage.
- Local storage paths are internal constants (not user-configurable). The repo’s tests use `KIOSK_RETROPIE_ROOT`
  to safely exercise those paths.

## Flashing / cloud-init example

The flashing path relies on cloud-init to write the config file and run a one-time installer service.

Mandatory variables for this scenario:

- `KIOSK_URL`
- `NFS_SERVER`

Optional options are commented out in the config payload embedded in the user-data.

How to use it:

1. In Raspberry Pi Imager, paste the file content into the OS customization “user-data” field (cloud-init).
1. Inside the embedded `/etc/kiosk-retropie/config.env` payload, set `KIOSK_URL` (and optionally set
  the repo pin in the `kiosk-retropie-install.service` unit if you want deterministic installs).
1. Boot the Pi. On first boot, cloud-init writes `/etc/kiosk-retropie/config.env`, installs a small bootstrap
  script + `kiosk-retropie-install.service`, and enables the service so it retries until install succeeds.
