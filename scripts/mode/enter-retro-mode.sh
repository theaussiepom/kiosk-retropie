#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "enter-retro-mode [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

retro_ha_libdir() {
  echo "${RETRO_HA_LIBDIR:-$(retro_ha_path /usr/local/lib/retro-ha)}"
}

retro_ha_ledctl_path() {
  # Support both:
  # - installed layout: /usr/local/lib/retro-ha/ledctl.sh
  # - repo layout: scripts/leds/ledctl.sh
  # Optional arg: script_dir override (defaults to this script's directory).
  local script_dir="${1:-$SCRIPT_DIR}"
  local candidate=""

  if [[ -n "${RETRO_HA_LIBDIR:-}" ]]; then
    candidate="$RETRO_HA_LIBDIR/ledctl.sh"
    if [[ -x "$candidate" ]]; then
      cover_path "enter-retro-mode:ledctl-libdir"
      echo "$candidate"
      return 0
    fi
  fi

  candidate="$script_dir/ledctl.sh"
  if [[ -x "$candidate" ]]; then
    cover_path "enter-retro-mode:ledctl-scriptdir"
    echo "$candidate"
    return 0
  fi

  candidate="$script_dir/../leds/ledctl.sh"
  if [[ -x "$candidate" ]]; then
    cover_path "enter-retro-mode:ledctl-scriptdir-leds"
    echo "$candidate"
    return 0
  fi

  # Fallback: installed default.
  cover_path "enter-retro-mode:ledctl-fallback"
  echo "$(retro_ha_libdir)/ledctl.sh"
}

main() {
  export RETRO_HA_LOG_PREFIX="enter-retro-mode"

  log "Switching to RetroPie mode"

  # Stop HA kiosk first to preserve single X ownership.
  svc_stop ha-kiosk.service || true

  # RetroPie mode should force LEDs on.
  local ledctl
  ledctl="$(retro_ha_ledctl_path "$SCRIPT_DIR")"
  if [[ -x "$ledctl" ]]; then
    run_cmd "$ledctl" all on || true
  fi

  svc_start retro-mode.service
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
