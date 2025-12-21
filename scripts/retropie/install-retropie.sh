#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "retropie-install [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

require_root() {
  if [[ "${RETRO_HA_ALLOW_NON_ROOT:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Must run as root"
  fi
}

main() {
  export RETRO_HA_LOG_PREFIX="retropie-install"

  require_root

  local user="retropi"
  if ! id -u "$user" > /dev/null 2>&1; then
    cover_path "retropie-install:user-missing"
    die "User $user not found (installer should create it)"
  fi

  if ! command -v git > /dev/null 2>&1; then
    cover_path "retropie-install:git-missing"
    die "git not found"
  fi
  if ! command -v sudo > /dev/null 2>&1; then
    cover_path "retropie-install:sudo-missing"
    die "sudo not found"
  fi

  local home_dir
  home_dir="$(getent passwd "$user" | cut -d: -f6)"
  if [[ -z "$home_dir" ]]; then
    cover_path "retropie-install:home-missing"
    die "Unable to resolve home directory for $user"
  fi

  local setup_dir="${RETRO_HA_RETROPIE_SETUP_DIR:-$home_dir/RetroPie-Setup}"
  local setup_repo="${RETRO_HA_RETROPIE_SETUP_REPO:-https://github.com/RetroPie/RetroPie-Setup.git}"

  if [[ ! -d "$setup_dir/.git" ]]; then
    cover_path "retropie-install:clone"
    log "Cloning RetroPie-Setup into $setup_dir"
    run_cmd rm -rf "$setup_dir"
    run_cmd sudo -u "$user" git clone --depth 1 "$setup_repo" "$setup_dir"
  else
    cover_path "retropie-install:update"
    log "RetroPie-Setup already present; updating"
    run_cmd sudo -u "$user" git -C "$setup_dir" pull --ff-only || true
  fi

  log "Starting unattended basic_install (this may take a long time)"
  # This is the least interactive path RetroPie-Setup supports.
  # If it fails, we do not want to brick the appliance; caller can decide what to do.
  if [[ "${RETRO_HA_DRY_RUN:-0}" == "1" ]]; then
    cover_path "retropie-install:dry-run"
    record_call "cd $setup_dir"
  else
    cd "$setup_dir"
  fi
  run_cmd ./retropie_packages.sh setup basic_install

  log "RetroPie install completed"
}

if ! retro_ha_is_sourced; then
  main "$@"
fi
