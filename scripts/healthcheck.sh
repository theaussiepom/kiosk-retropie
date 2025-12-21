#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "healthcheck [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

is_active() {
  systemctl is-active --quiet "$1"
}

healthcheck_enter_retro_path() {
  # Determine which enter-retro-mode.sh to run.
  # Optional arg: script_dir override (defaults to this script's directory).
  local script_dir="${1:-$SCRIPT_DIR}"

  local enter
  if [[ -n "${RETRO_HA_LIBDIR:-}" && -x "$RETRO_HA_LIBDIR/enter-retro-mode.sh" ]]; then
    cover_path "healthcheck:enter-retro-libdir"
    enter="$RETRO_HA_LIBDIR/enter-retro-mode.sh"
  elif [[ -x "$script_dir/enter-retro-mode.sh" ]]; then
    cover_path "healthcheck:enter-retro-scriptdir"
    enter="$script_dir/enter-retro-mode.sh"
  elif [[ -x "$script_dir/mode/enter-retro-mode.sh" ]]; then
    cover_path "healthcheck:enter-retro-scriptdir-mode"
    enter="$script_dir/mode/enter-retro-mode.sh"
  else
    cover_path "healthcheck:enter-retro-fallback"
    enter="$(retro_ha_path /usr/local/lib/retro-ha)/enter-retro-mode.sh"
  fi

  printf '%s\n' "$enter"
}

main() {
  export RETRO_HA_LOG_PREFIX="healthcheck"

  # Fail-open principle: if we're not in HA mode or Retro mode, enter Retro mode.
  # This is intentionally simple and avoids network/URL probing.
  if is_active ha-kiosk.service; then
    log "HA kiosk active"
    exit 0
  fi
  if is_active retro-mode.service; then
    log "Retro mode active"
    exit 0
  fi

  log "No active mode detected; failing over to Retro mode"
  local enter
  enter="$(healthcheck_enter_retro_path "$SCRIPT_DIR")"

  run_cmd "$enter" || true
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
