#!/usr/bin/env bash
set -euo pipefail

# MQTT-controlled screen brightness (backlight) bridge.
#
# Requires:
#   - mosquitto_sub + mosquitto_pub (package: mosquitto-clients)
#   - a writable sysfs backlight device under /sys/class/backlight
#
# Topics (default prefix: retro-ha):
#   <prefix>/screen/brightness/set   payload: 0-100 (percent)
# State topic (retained):
#   <prefix>/screen/brightness/state payload: 0-100

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "retro-ha-screen-brightness-mqtt [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

__retro_ha_screen_brightness_mqtt_poller_pid=""
__retro_ha_screen_brightness_mqtt_sub_pid=""

screen_brightness_mqtt_cleanup() {
  if [[ -n "${__retro_ha_screen_brightness_mqtt_poller_pid:-}" ]]; then
    kill "${__retro_ha_screen_brightness_mqtt_poller_pid}" 2> /dev/null || true
  fi
  if [[ -n "${__retro_ha_screen_brightness_mqtt_sub_pid:-}" ]]; then
    kill "${__retro_ha_screen_brightness_mqtt_sub_pid}" 2> /dev/null || true
  fi
  exec 3<&- 2> /dev/null || true
}

mosq_args() {
  local args=()

  args+=("-h" "${MQTT_HOST}")
  if [[ -n "${MQTT_PORT:-}" ]]; then
    cover_path "screen-brightness-mqtt:mosq-port-explicit"
  else
    cover_path "screen-brightness-mqtt:mosq-port-default"
  fi
  args+=("-p" "${MQTT_PORT:-1883}")

  if [[ -n "${MQTT_USERNAME:-}" ]]; then
    cover_path "screen-brightness-mqtt:mosq-username"
    args+=("-u" "${MQTT_USERNAME}")
  else
    cover_path "screen-brightness-mqtt:mosq-no-username"
  fi
  if [[ -n "${MQTT_PASSWORD:-}" ]]; then
    cover_path "screen-brightness-mqtt:mosq-password"
    args+=("-P" "${MQTT_PASSWORD}")
  else
    cover_path "screen-brightness-mqtt:mosq-no-password"
  fi

  if [[ "${MQTT_TLS:-0}" == "1" ]]; then
    cover_path "screen-brightness-mqtt:mosq-tls-on"
    args+=("--tls-version" "tlsv1.2")
  else
    cover_path "screen-brightness-mqtt:mosq-tls-off"
  fi

  printf '%s\n' "${args[@]}"
}

backlight_dir() {
  local sysfs_root
  sysfs_root="$(retro_ha_path /sys/class/backlight)"

  local name="${RETRO_HA_BACKLIGHT_NAME:-}"
  if [[ -n "$name" ]]; then
    cover_path "screen-brightness-mqtt:backlight-name"
    printf '%s\n' "${sysfs_root}/${name}"
    return 0
  fi

  cover_path "screen-brightness-mqtt:backlight-auto"
  shopt -s nullglob
  local d
  for d in "${sysfs_root}"/*; do
    if [[ -d "$d" ]]; then
      printf '%s\n' "$d"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob

  printf '%s\n' ""
}

read_max_brightness() {
  local dir="$1"
  local f="$dir/max_brightness"
  if [[ ! -f "$f" ]]; then
    cover_path "screen-brightness-mqtt:max-missing"
    return 1
  fi

  cover_path "screen-brightness-mqtt:max-present"
  tr -d '[:space:]' < "$f"
}

write_brightness_raw() {
  local dir="$1"
  local raw="$2"

  local f="$dir/brightness"
  if [[ "${RETRO_HA_DRY_RUN:-0}" == "1" ]]; then
    cover_path "screen-brightness-mqtt:write-dry-run"
    record_call "write_brightness $raw $f"
    return 0
  fi

  cover_path "screen-brightness-mqtt:write-exec"
  printf '%s\n' "$raw" > "$f"
}

read_brightness_percent() {
  local dir="$1"

  local max
  if ! max="$(read_max_brightness "$dir")"; then
    return 1
  fi

  if [[ ! "$max" =~ ^[0-9]+$ ]] || ((max <= 0)); then
    cover_path "screen-brightness-mqtt:max-invalid"
    return 1
  fi

  local raw_file="$dir/brightness"
  if [[ ! -f "$raw_file" ]]; then
    cover_path "screen-brightness-mqtt:read-missing"
    return 1
  fi

  local raw
  raw="$(tr -d '[:space:]' < "$raw_file" 2> /dev/null || true)"
  if [[ ! "$raw" =~ ^[0-9]+$ ]]; then
    cover_path "screen-brightness-mqtt:read-invalid"
    return 1
  fi

  # Round to nearest whole percent.
  local percent
  percent=$(((raw * 100 + (max / 2)) / max))
  if ((percent > 100)); then
    percent=100
  fi

  cover_path "screen-brightness-mqtt:read-percent"
  printf '%s\n' "$percent"
}

publish_brightness_state_once() {
  local prefix="$1"

  local dir
  dir="$(backlight_dir)"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    return 0
  fi

  local percent
  if percent="$(read_brightness_percent "$dir")"; then
    cover_path "screen-brightness-mqtt:state-publish"
    publish_state "$percent" "$prefix" || true
  fi
}

brightness_state_poller() {
  local prefix="$1"

  local poll_sec="${RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC:-2}"
  local max_loops="${RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS:-0}"
  local loops=0

  local last=""

  while true; do
    local dir
    dir="$(backlight_dir)"
    if [[ -n "$dir" && -d "$dir" ]]; then
      local percent
      if percent="$(read_brightness_percent "$dir")"; then
        if [[ "$percent" != "$last" ]]; then
          cover_path "screen-brightness-mqtt:state-change"
          publish_state "$percent" "$prefix" || true
          last="$percent"
        else
          cover_path "screen-brightness-mqtt:state-same"
        fi
      fi
    fi

    loops=$((loops + 1))
    if [[ "$max_loops" != "0" && "$loops" -ge "$max_loops" ]]; then
      cover_path "screen-brightness-mqtt:state-max-loops"
      return 0
    fi

    sleep "$poll_sec"
  done
}

publish_state() {
  local percent="$1"
  local prefix="$2"

  cover_path "screen-brightness-mqtt:publish-state"

  local state_topic
  state_topic="${prefix}/screen/brightness/state"

  local args=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    args+=("$line")
  done <<< "$(mosq_args)"

  run_cmd mosquitto_pub "${args[@]}" -t "$state_topic" -m "$percent" -r
}

handle_set() {
  local payload_raw="$1"
  local prefix="$2"

  local payload
  payload="$(tr -d '[:space:]' <<< "$payload_raw")"

  if [[ ! "$payload" =~ ^[0-9]{1,3}$ ]]; then
    cover_path "screen-brightness-mqtt:invalid-payload"
    log "Ignoring non-numeric brightness payload '$payload_raw'"
    return 0
  fi

  local percent="$payload"
  if ((percent < 0 || percent > 100)); then
    cover_path "screen-brightness-mqtt:invalid-payload"
    log "Ignoring out-of-range brightness payload '$payload_raw'"
    return 0
  fi

  local dir
  dir="$(backlight_dir)"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    cover_path "screen-brightness-mqtt:no-backlight"
    die "No backlight device found under $(retro_ha_path /sys/class/backlight)"
  fi

  local max
  if ! max="$(read_max_brightness "$dir")"; then
    die "Backlight max_brightness missing: $dir/max_brightness"
  fi

  if [[ ! "$max" =~ ^[0-9]+$ ]] || ((max <= 0)); then
    cover_path "screen-brightness-mqtt:max-invalid"
    die "Invalid max_brightness: $max"
  fi

  local raw
  raw=$((percent * max / 100))

  cover_path "screen-brightness-mqtt:set"
  write_brightness_raw "$dir" "$raw"

  publish_state "$percent" "$prefix" || true
}

main() {
  export RETRO_HA_LOG_PREFIX="retro-ha-screen-brightness-mqtt"

  if [[ "${RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED:-0}" != "1" ]]; then
    cover_path "screen-brightness-mqtt:disabled"
    log "RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED!=1; exiting (disabled)."
    exit 0
  fi

  if [[ -z "${MQTT_HOST:-}" ]]; then
    cover_path "screen-brightness-mqtt:missing-mqtt-host"
    die "MQTT_HOST is required"
  fi

  local prefix="${RETRO_HA_MQTT_TOPIC_PREFIX:-retro-ha}"
  local topic_filter="${prefix}/screen/brightness/set"

  local args=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    args+=("$line")
  done <<< "$(mosq_args)"

  log "Subscribing to ${topic_filter}"
  cover_path "screen-brightness-mqtt:subscribing"

  # Publish initial state so HA is in sync even if brightness was changed outside MQTT.
  cover_path "screen-brightness-mqtt:state-initial"
  publish_brightness_state_once "$prefix"

  # Background poller: keep HA in sync with any non-MQTT changes.
  brightness_state_poller "$prefix" &
  __retro_ha_screen_brightness_mqtt_poller_pid=$!

  # Start subscriber via process substitution so we can track its PID and clean up.
  exec 3< <(mosquitto_sub "${args[@]}" -v -t "$topic_filter")
  __retro_ha_screen_brightness_mqtt_sub_pid=$!

  trap screen_brightness_mqtt_cleanup EXIT INT TERM

  while read -r _topic payload <&3; do
    handle_set "$payload" "$prefix" || true
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
