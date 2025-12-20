#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "ledctl [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

usage() {
  cat << 'EOF'
Usage:
  ledctl.sh (act|pwr|all) (on|off)

Environment overrides (typically from /etc/retro-ha/config.env):
  RETRO_HA_ACT_LED              LED sysfs name for "ACT" (default: led0)
  RETRO_HA_PWR_LED              LED sysfs name for "PWR" (default: led1)
  RETRO_HA_ACT_LED_TRIGGER_ON   Trigger to restore when turning ACT on (default: mmc0)
  RETRO_HA_PWR_LED_TRIGGER_ON   Trigger to restore when turning PWR on (default: default-on)

Notes:
  - "off" forces trigger=none and brightness=0.
  - "on" sets brightness=1 and tries to set the configured trigger.
EOF
}

led_sysfs_dir() {
  local led_name="$1"
  retro_ha_path "/sys/class/leds/${led_name}"
}

set_led_off() {
  local led_name="$1"
  local dir
  dir="$(led_sysfs_dir "$led_name")"

  if [[ ! -d "$dir" ]]; then
    echo "LED sysfs not found: $dir" >&2
    return 1
  fi

  echo none > "$dir/trigger"
  echo 0 > "$dir/brightness"
}

trigger_supported() {
  local trigger_file="$1"
  local desired="$2"

  [[ -f "$trigger_file" ]] || return 1

  # Example trigger file content: "none [mmc0] timer heartbeat ..."
  # We match whole words, ignoring [brackets].
  local normalized
  normalized="$(tr -d '[]' < "$trigger_file")"
  grep -Eq "(^|[[:space:]])${desired}([[:space:]]|$)" <<< "$normalized"
}

set_led_on() {
  local led_name="$1"
  local desired_trigger="$2"
  local dir
  dir="$(led_sysfs_dir "$led_name")"

  if [[ ! -d "$dir" ]]; then
    echo "LED sysfs not found: $dir" >&2
    return 1
  fi

  # Determine support before we change the trigger file.
  local supported=0
  if trigger_supported "$dir/trigger" "$desired_trigger"; then
    supported=1
  fi

  # Ensure the LED is lit even if trigger restore fails.
  echo none > "$dir/trigger"
  echo 1 > "$dir/brightness"

  if [[ "$supported" == "1" ]]; then
    echo "$desired_trigger" > "$dir/trigger"
  fi
}

main() {
  export RETRO_HA_LOG_PREFIX="ledctl"

  if [[ $# -ne 2 ]]; then
    cover_path "ledctl:usage-argc"
    usage >&2
    exit 2
  fi

  local which="$1"
  local state="$2"

  local act_led="${RETRO_HA_ACT_LED:-led0}"
  local pwr_led="${RETRO_HA_PWR_LED:-led1}"

  local act_on_trigger="${RETRO_HA_ACT_LED_TRIGGER_ON:-mmc0}"
  local pwr_on_trigger="${RETRO_HA_PWR_LED_TRIGGER_ON:-default-on}"

  case "$which" in
    act | pwr | all) : ;;
    *)
      cover_path "ledctl:invalid-target"
      echo "Invalid target: $which" >&2
      usage >&2
      exit 2
      ;;
  esac

  case "$state" in
    on | off) : ;;
    *)
      cover_path "ledctl:invalid-state"
      echo "Invalid state: $state" >&2
      usage >&2
      exit 2
      ;;
  esac

  if [[ "$which" == "act" || "$which" == "all" ]]; then
    if [[ "$state" == "off" ]]; then
      cover_path "ledctl:act-off"
      set_led_off "$act_led"
    else
      # Distinguish trigger support.
      if trigger_supported "$(led_sysfs_dir "$act_led")/trigger" "$act_on_trigger"; then
        cover_path "ledctl:act-on-supported"
      else
        cover_path "ledctl:act-on-unsupported"
      fi
      set_led_on "$act_led" "$act_on_trigger"
    fi
  fi

  if [[ "$which" == "pwr" || "$which" == "all" ]]; then
    if [[ "$state" == "off" ]]; then
      cover_path "ledctl:pwr-off"
      set_led_off "$pwr_led"
    else
      if trigger_supported "$(led_sysfs_dir "$pwr_led")/trigger" "$pwr_on_trigger"; then
        cover_path "ledctl:pwr-on-supported"
      else
        cover_path "ledctl:pwr-on-unsupported"
      fi
      set_led_on "$pwr_led" "$pwr_on_trigger"
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
