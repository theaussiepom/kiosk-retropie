#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

MARKER_FILE="${RETRO_HA_INSTALLED_MARKER:-$(retro_ha_path /var/lib/retro-ha/installed)}"
LOCK_FILE="${RETRO_HA_INSTALL_LOCK:-$(retro_ha_path /var/lock/retro-ha-install.lock)}"

log() {
  # Backwards-compat wrapper (prefer scripts/lib/logging.sh).
  echo "retro-ha install: $*" >&2
}

die() {
  log "$*"
  exit 1
}

require_root() {
  if [[ "${RETRO_HA_ALLOW_NON_ROOT:-0}" == "1" ]]; then
    cover_path "install:allow-non-root"
    return 0
  fi
  local effective_uid="${RETRO_HA_EUID_OVERRIDE:-${EUID:-$(id -u)}}"
  if [[ "$effective_uid" -ne 0 ]]; then
    cover_path "install:root-required"
    die "Must run as root"
  fi
  cover_path "install:root-ok"
}

ensure_user() {
  local user="retropi"
  if id -u "$user" > /dev/null 2>&1; then
    cover_path "install:user-exists"
    return 0
  fi

  cover_path "install:user-created"

  # Create a dedicated kiosk user.
  run_cmd useradd -m -s /bin/bash "$user"

  # Typical Raspberry Pi groups for X/input/audio.
  for g in video input audio render plugdev dialout; do
    if getent group "$g" > /dev/null 2>&1; then
      run_cmd usermod -aG "$g" "$user"
    fi
  done
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive

  # NOTE: Keep the base set minimal; we can extend as services are implemented.
  run_cmd apt-get update
  run_cmd apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    nfs-common \
    python3 \
    rsync \
    xserver-xorg \
    xinit

  # Chromium package name varies by release.
  if apt-cache show chromium-browser > /dev/null 2>&1; then
    cover_path "install:chromium-browser-pkg"
    run_cmd apt-get install -y --no-install-recommends chromium-browser
  elif apt-cache show chromium > /dev/null 2>&1; then
    cover_path "install:chromium-pkg"
    run_cmd apt-get install -y --no-install-recommends chromium
  else
    cover_path "install:chromium-none"
    log "Chromium package not found via apt-cache (skipping for now)"
  fi
}

install_files() {
  local repo_root
  repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"

  local etc_dir
  local lib_dir
  local bin_dir
  local systemd_dir
  etc_dir="$(retro_ha_path /etc/retro-ha)"
  lib_dir="${RETRO_HA_LIBDIR:-$(retro_ha_path /usr/local/lib/retro-ha)}"
  bin_dir="${RETRO_HA_BINDIR:-$(retro_ha_path /usr/local/bin)}"
  systemd_dir="${RETRO_HA_SYSTEMD_DIR:-$(retro_ha_path /etc/systemd/system)}"

  run_cmd mkdir -p "$etc_dir"
  run_cmd mkdir -p "$lib_dir"
  run_cmd mkdir -p "$lib_dir/lib"
  run_cmd mkdir -p "$bin_dir"
  run_cmd mkdir -p "$systemd_dir"

  # Install bootstrap + core installer assets.
  run_cmd install -m 0755 "$repo_root/scripts/bootstrap.sh" "$lib_dir/bootstrap.sh"

  # Install shared lib helpers.
  if [[ -d "$repo_root/scripts/lib" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/lib/common.sh" "$lib_dir/lib/common.sh"
    run_cmd install -m 0755 "$repo_root/scripts/lib/config.sh" "$lib_dir/lib/config.sh"
    run_cmd install -m 0755 "$repo_root/scripts/lib/logging.sh" "$lib_dir/lib/logging.sh"
    if [[ -f "$repo_root/scripts/lib/path.sh" ]]; then
      run_cmd install -m 0755 "$repo_root/scripts/lib/path.sh" "$lib_dir/lib/path.sh"
    fi
    if [[ -f "$repo_root/scripts/lib/x11.sh" ]]; then
      run_cmd install -m 0755 "$repo_root/scripts/lib/x11.sh" "$lib_dir/lib/x11.sh"
    fi
    if [[ -f "$repo_root/scripts/lib/backup.sh" ]]; then
      run_cmd install -m 0755 "$repo_root/scripts/lib/backup.sh" "$lib_dir/lib/backup.sh"
    fi
  fi

  # Install scripts (only those that exist today).
  if [[ -d "$repo_root/scripts/leds" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/leds/ledctl.sh" "$lib_dir/ledctl.sh"
    run_cmd install -m 0755 "$repo_root/scripts/leds/led-mqtt.sh" "$lib_dir/retro-ha-led-mqtt.sh"
    run_cmd ln -sf "$lib_dir/retro-ha-led-mqtt.sh" "$bin_dir/retro-ha-led-mqtt.sh"
  fi

  if [[ -d "$repo_root/scripts/screen" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/screen/screen-brightness-mqtt.sh" "$lib_dir/retro-ha-screen-brightness-mqtt.sh"
    run_cmd ln -sf "$lib_dir/retro-ha-screen-brightness-mqtt.sh" "$bin_dir/retro-ha-screen-brightness-mqtt.sh"
  fi

  if [[ -f "$repo_root/scripts/mode/ha-kiosk.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/mode/ha-kiosk.sh" "$lib_dir/ha-kiosk.sh"
  fi
  if [[ -f "$repo_root/scripts/mode/retro-mode.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/mode/retro-mode.sh" "$lib_dir/retro-mode.sh"
  fi
  if [[ -f "$repo_root/scripts/mode/enter-ha-mode.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/mode/enter-ha-mode.sh" "$lib_dir/enter-ha-mode.sh"
  fi
  if [[ -f "$repo_root/scripts/mode/enter-retro-mode.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/mode/enter-retro-mode.sh" "$lib_dir/enter-retro-mode.sh"
  fi

  if [[ -f "$repo_root/scripts/input/controller-listener-tty.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/input/controller-listener-tty.sh" "$lib_dir/controller-listener-tty.sh"
  fi
  if [[ -f "$repo_root/scripts/input/controller-listener-ha-mode.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/input/controller-listener-ha-mode.sh" "$lib_dir/controller-listener-ha-mode.sh"
  fi
  if [[ -f "$repo_root/scripts/healthcheck.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/healthcheck.sh" "$lib_dir/healthcheck.sh"
  fi
  if [[ -f "$repo_root/scripts/nfs/mount-nfs.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/nfs/mount-nfs.sh" "$lib_dir/mount-nfs.sh"
  fi
  if [[ -f "$repo_root/scripts/nfs/mount-nfs-backup.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/nfs/mount-nfs-backup.sh" "$lib_dir/mount-nfs-backup.sh"
  fi
  if [[ -f "$repo_root/scripts/nfs/sync-roms.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/nfs/sync-roms.sh" "$lib_dir/sync-roms.sh"
  fi
  if [[ -f "$repo_root/scripts/nfs/save-backup.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/nfs/save-backup.sh" "$lib_dir/save-backup.sh"
  fi
  if [[ -f "$repo_root/scripts/retropie/install-retropie.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/retropie/install-retropie.sh" "$lib_dir/install-retropie.sh"
  fi
  if [[ -f "$repo_root/scripts/retropie/configure-retropie-storage.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/retropie/configure-retropie-storage.sh" "$lib_dir/configure-retropie-storage.sh"
  fi

  # Backwards-compatible symlinks (older underscore-style names).
  run_cmd ln -sf "$lib_dir/ha-kiosk.sh" "$lib_dir/ha_kiosk.sh"
  run_cmd ln -sf "$lib_dir/retro-mode.sh" "$lib_dir/retro_mode.sh"
  run_cmd ln -sf "$lib_dir/enter-ha-mode.sh" "$lib_dir/enter_ha_mode.sh"
  run_cmd ln -sf "$lib_dir/enter-retro-mode.sh" "$lib_dir/enter_retro_mode.sh"
  run_cmd ln -sf "$lib_dir/controller-listener-tty.sh" "$lib_dir/controller_listener_tty.sh"
  run_cmd ln -sf "$lib_dir/controller-listener-ha-mode.sh" "$lib_dir/controller_listener_ha_mode.sh"
  run_cmd ln -sf "$lib_dir/mount-nfs.sh" "$lib_dir/mount_nfs.sh"
  run_cmd ln -sf "$lib_dir/sync-roms.sh" "$lib_dir/sync_roms.sh"
  run_cmd ln -sf "$lib_dir/mount-nfs-backup.sh" "$lib_dir/mount_nfs_backup.sh"
  run_cmd ln -sf "$lib_dir/save-backup.sh" "$lib_dir/save_backup.sh"
  run_cmd ln -sf "$lib_dir/install-retropie.sh" "$lib_dir/install_retropie.sh"
  run_cmd ln -sf "$lib_dir/configure-retropie-storage.sh" "$lib_dir/configure_retropie_storage.sh"

  # Install systemd units.
  run_cmd install -m 0644 "$repo_root/systemd/retro-ha-install.service" "$systemd_dir/retro-ha-install.service"
  if [[ -f "$repo_root/systemd/retro-ha-led-mqtt.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/retro-ha-led-mqtt.service" "$systemd_dir/retro-ha-led-mqtt.service"
  fi
  if [[ -f "$repo_root/systemd/retro-ha-screen-brightness-mqtt.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/retro-ha-screen-brightness-mqtt.service" "$systemd_dir/retro-ha-screen-brightness-mqtt.service"
  fi
  if [[ -f "$repo_root/systemd/emergency-retro-launch.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/emergency-retro-launch.service" "$systemd_dir/emergency-retro-launch.service"
  fi
  if [[ -f "$repo_root/systemd/ha-kiosk.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/ha-kiosk.service" "$systemd_dir/ha-kiosk.service"
  fi
  if [[ -f "$repo_root/systemd/retro-mode.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/retro-mode.service" "$systemd_dir/retro-mode.service"
  fi
  if [[ -f "$repo_root/systemd/ha-mode-controller-listener.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/ha-mode-controller-listener.service" "$systemd_dir/ha-mode-controller-listener.service"
  fi
  if [[ -f "$repo_root/systemd/retro-ha-failover.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/retro-ha-failover.service" "$systemd_dir/retro-ha-failover.service"
  fi
  if [[ -f "$repo_root/systemd/boot-sync.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/boot-sync.service" "$systemd_dir/boot-sync.service"
  fi
  if [[ -f "$repo_root/systemd/healthcheck.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/healthcheck.service" "$systemd_dir/healthcheck.service"
  fi
  if [[ -f "$repo_root/systemd/healthcheck.timer" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/healthcheck.timer" "$systemd_dir/healthcheck.timer"
  fi
  if [[ -f "$repo_root/systemd/save-backup.service" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/save-backup.service" "$systemd_dir/save-backup.service"
  fi
  if [[ -f "$repo_root/systemd/save-backup.timer" ]]; then
    run_cmd install -m 0644 "$repo_root/systemd/save-backup.timer" "$systemd_dir/save-backup.timer"
  fi
}

enable_services() {
  run_cmd systemctl daemon-reload

  # Always enable the emergency listener.
  run_cmd systemctl enable emergency-retro-launch.service > /dev/null 2>&1 || true

  # Default to HA kiosk on boot; Retro mode is started on-demand.
  run_cmd systemctl enable ha-kiosk.service > /dev/null 2>&1 || true
  run_cmd systemctl enable ha-mode-controller-listener.service > /dev/null 2>&1 || true

  # Optional ROM sync (Pattern A). Script is a no-op unless configured.
  run_cmd systemctl enable boot-sync.service > /dev/null 2>&1 || true

  # Optional components.
  run_cmd systemctl enable retro-ha-led-mqtt.service > /dev/null 2>&1 || true
  run_cmd systemctl enable retro-ha-screen-brightness-mqtt.service > /dev/null 2>&1 || true

  # Fail-open safety net (periodic).
  run_cmd systemctl enable healthcheck.timer > /dev/null 2>&1 || true

  # Optional save/state backup. Script is a no-op unless enabled.
  run_cmd systemctl enable save-backup.timer > /dev/null 2>&1 || true
}

write_marker() {
  run_cmd mkdir -p "$(dirname "$MARKER_FILE")"
  if [[ "${RETRO_HA_DRY_RUN:-0}" == "1" ]]; then
    cover_path "install:write-marker-dry-run"
    record_call "write_marker $MARKER_FILE"
    return 0
  fi
  cover_path "install:write-marker-write"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER_FILE"
}

main() {
  require_root
  load_config_env
  export RETRO_HA_LOG_PREFIX="retro-ha install"

  if [[ -f "$MARKER_FILE" ]]; then
    cover_path "install:marker-present-early"
    log "Already installed ($MARKER_FILE present)"
    exit 0
  fi

  run_cmd mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9> "$LOCK_FILE"
  if ! flock -n 9; then
    cover_path "install:lock-busy"
    die "Another installer instance is running"
  fi
  cover_path "install:lock-acquired"

  if [[ -f "$MARKER_FILE" ]]; then
    cover_path "install:marker-after-lock"
    log "Already installed (marker appeared while waiting for lock)"
    exit 0
  fi

  log "Ensuring user retropi"
  ensure_user

  log "Installing packages"
  install_packages

  log "Installing files"
  install_files

  if [[ "${RETRO_HA_INSTALL_RETROPIE:-0}" == "1" ]]; then
    cover_path "install:optional-retropie-enabled"
    log "Installing RetroPie (optional)"
    run_cmd "${RETRO_HA_LIBDIR:-$(retro_ha_path /usr/local/lib/retro-ha)}/install-retropie.sh" || log "RetroPie install failed (continuing)"
  else
    cover_path "install:optional-retropie-disabled"
  fi

  log "Configuring RetroPie storage (local saves)"
  run_cmd "${RETRO_HA_LIBDIR:-$(retro_ha_path /usr/local/lib/retro-ha)}/configure-retropie-storage.sh" || log "Storage configuration failed (continuing)"

  log "Enabling services"
  enable_services

  log "Writing marker"
  write_marker

  log "Install complete"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
