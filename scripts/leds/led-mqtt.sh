#!/usr/bin/env bash
set -euo pipefail

# A tiny MQTT subscriber that lets an MQTT client toggle the Pi LEDs.
#
# Requires:
#   - mosquitto_sub + mosquitto_pub (package: mosquitto-clients)
#   - scripts/leds/ledctl.sh installed at /usr/local/lib/kiosk-retropie/ledctl.sh
#
# Topics (default prefix: kiosk-retropie):
#   <prefix>/led/act/set   payload: ON|OFF
#   <prefix>/led/pwr/set   payload: ON|OFF
#   <prefix>/led/all/set   payload: ON|OFF
#
# State topics:
#   <prefix>/led/act/state payload: ON|OFF
#   <prefix>/led/pwr/state payload: ON|OFF

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "kiosk-retropie-led-mqtt [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

LEDCTL_PATH="${KIOSK_LEDCTL_PATH:-${KIOSK_RETROPIE_LEDCTL_PATH:-$(kiosk_retropie_path /usr/local/lib/kiosk-retropie/ledctl.sh)}}"

__kiosk_retropie_led_mqtt_poller_pid=""
__kiosk_retropie_led_mqtt_sub_pid=""

led_mqtt_cleanup() {
  if [[ -n "${__kiosk_retropie_led_mqtt_poller_pid:-}" ]]; then
    kill "${__kiosk_retropie_led_mqtt_poller_pid}" 2> /dev/null || true
  fi
  if [[ -n "${__kiosk_retropie_led_mqtt_sub_pid:-}" ]]; then
    kill "${__kiosk_retropie_led_mqtt_sub_pid}" 2> /dev/null || true
  fi
  exec 3<&- 2> /dev/null || true
}

mosq_args() {
  local args=()

  args+=("-h" "${MQTT_HOST}")
  if [[ -n "${MQTT_PORT:-}" ]]; then
    cover_path "led-mqtt:mosq-port-explicit"
  else
    cover_path "led-mqtt:mosq-port-default"
  fi
  args+=("-p" "${MQTT_PORT:-1883}")

  if [[ -n "${MQTT_USERNAME:-}" ]]; then
    cover_path "led-mqtt:mosq-username"
    args+=("-u" "${MQTT_USERNAME}")
  else
    cover_path "led-mqtt:mosq-no-username"
  fi
  if [[ -n "${MQTT_PASSWORD:-}" ]]; then
    cover_path "led-mqtt:mosq-password"
    args+=("-P" "${MQTT_PASSWORD}")
  else
    cover_path "led-mqtt:mosq-no-password"
  fi

  # Optional TLS (keep minimal; assume system CA store).
  if [[ "${MQTT_TLS:-0}" == "1" ]]; then
    cover_path "led-mqtt:mosq-tls-on"
    args+=("--tls-version" "tlsv1.2")
  else
    cover_path "led-mqtt:mosq-tls-off"
  fi

  printf '%s\n' "${args[@]}"
}

publish_state() {
  local target="$1"  # act|pwr
  local payload="$2" # ON|OFF
  local prefix="$3"

  cover_path "led-mqtt:publish-state"

  local state_topic
  state_topic="${prefix}/led/${target}/state"

  local args=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    args+=("$line")
  done <<< "$(mosq_args)"
  run_cmd mosquitto_pub "${args[@]}" -t "$state_topic" -m "$payload" -r
}

led_state_payload() {
  local target="$1" # act|pwr

  local led_name=""
  case "$target" in
    act) led_name="${KIOSK_ACT_LED:-${KIOSK_RETROPIE_ACT_LED:-ledact}}" ;;
    pwr) led_name="${KIOSK_PWR_LED:-${KIOSK_RETROPIE_PWR_LED:-ledpwr}}" ;;
    *)
      cover_path "led-mqtt:state-invalid-target"
      return 1
      ;;
  esac

  local dir
  dir="$(kiosk_retropie_path "/sys/class/leds/${led_name}")"
  local brightness_file="$dir/brightness"
  if [[ ! -f "$brightness_file" ]]; then
    cover_path "led-mqtt:state-brightness-missing"
    return 1
  fi

  local raw
  raw="$(tr -d '[:space:]' < "$brightness_file" 2> /dev/null || true)"
  if [[ ! "$raw" =~ ^[0-9]+$ ]]; then
    cover_path "led-mqtt:state-brightness-invalid"
    return 1
  fi

  if ((raw > 0)); then
    cover_path "led-mqtt:state-on"
    printf '%s\n' "ON"
  else
    cover_path "led-mqtt:state-off"
    printf '%s\n' "OFF"
  fi
}

publish_led_states_once() {
  local prefix="$1"

  local payload
  if payload="$(led_state_payload act)"; then
    cover_path "led-mqtt:state-publish-act"
    publish_state act "$payload" "$prefix" || true
  fi
  if payload="$(led_state_payload pwr)"; then
    cover_path "led-mqtt:state-publish-pwr"
    publish_state pwr "$payload" "$prefix" || true
  fi
}

led_state_poller() {
  local prefix="$1"

  local poll_sec="${KIOSK_LED_MQTT_POLL_SEC:-${KIOSK_RETROPIE_LED_MQTT_POLL_SEC:-2}}"
  local max_loops="${KIOSK_LED_MQTT_MAX_LOOPS:-${KIOSK_RETROPIE_LED_MQTT_MAX_LOOPS:-0}}"
  local loops=0

  local last_act=""
  local last_pwr=""

  while true; do
    local payload

    if payload="$(led_state_payload act)"; then
      if [[ "$payload" != "$last_act" ]]; then
        cover_path "led-mqtt:state-change-act"
        publish_state act "$payload" "$prefix" || true
        last_act="$payload"
      else
        cover_path "led-mqtt:state-same-act"
      fi
    fi

    if payload="$(led_state_payload pwr)"; then
      if [[ "$payload" != "$last_pwr" ]]; then
        cover_path "led-mqtt:state-change-pwr"
        publish_state pwr "$payload" "$prefix" || true
        last_pwr="$payload"
      else
        cover_path "led-mqtt:state-same-pwr"
      fi
    fi

    loops=$((loops + 1))
    if [[ "$max_loops" != "0" && "$loops" -ge "$max_loops" ]]; then
      cover_path "led-mqtt:state-max-loops"
      return 0
    fi

    sleep "$poll_sec"
  done
}

handle_set() {
  local target="$1" # act|pwr|all
  local payload_raw="$2"
  local prefix="$3"

  local payload
  payload="$(tr '[:lower:]' '[:upper:]' <<< "$payload_raw")"

  local state
  case "$payload" in
    ON)
      cover_path "led-mqtt:payload-on"
      state="on"
      ;;
    OFF)
      cover_path "led-mqtt:payload-off"
      state="off"
      ;;
    *)
      cover_path "led-mqtt:payload-invalid"
      log "Ignoring payload '$payload_raw' for target '$target'"
      return 0
      ;;
  esac

  if [[ ! -x "$LEDCTL_PATH" ]]; then
    cover_path "led-mqtt:ledctl-missing"
    die "LED control script missing or not executable: $LEDCTL_PATH"
  fi

  run_cmd "$LEDCTL_PATH" "$target" "$state"

  # Publish retained state for dashboard/UI.
  case "$target" in
    act | pwr)
      cover_path "led-mqtt:target-single"
      publish_state "$target" "$payload" "$prefix"
      ;;
    all)
      cover_path "led-mqtt:target-all"
      publish_state "act" "$payload" "$prefix" || true
      publish_state "pwr" "$payload" "$prefix" || true
      ;;
  esac
}

main() {
  export KIOSK_RETROPIE_LOG_PREFIX="kiosk-retropie-led-mqtt"

  if [[ "${KIOSK_LED_MQTT_ENABLED:-${KIOSK_RETROPIE_LED_MQTT_ENABLED:-0}}" != "1" ]]; then
    cover_path "led-mqtt:disabled"
    log "KIOSK_LED_MQTT_ENABLED!=1; exiting (disabled)."
    exit 0
  fi

  if [[ -z "${MQTT_HOST:-}" ]]; then
    cover_path "led-mqtt:missing-mqtt-host"
    die "MQTT_HOST is required"
  fi

  local prefix="${KIOSK_MQTT_TOPIC_PREFIX:-${KIOSK_RETROPIE_MQTT_TOPIC_PREFIX:-kiosk-retropie}}"
  local topic_filter="${prefix}/led/+/set"

  local args=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    args+=("$line")
  done <<< "$(mosq_args)"

  log "Subscribing to ${topic_filter}"

  cover_path "led-mqtt:subscribing"

  # Publish initial state so state is in sync even if a change happened outside MQTT.
  cover_path "led-mqtt:state-initial"
  publish_led_states_once "$prefix"

  # Background poller: keep state in sync with any non-MQTT changes.
  led_state_poller "$prefix" &
  __kiosk_retropie_led_mqtt_poller_pid=$!

  # Start subscriber via process substitution so we can track its PID and clean up.
  exec 3< <(mosquitto_sub "${args[@]}" -v -t "$topic_filter")
  __kiosk_retropie_led_mqtt_sub_pid=$!

  trap led_mqtt_cleanup EXIT INT TERM

  # -v prints "<topic> <payload>" per line.
  while read -r topic payload <&3; do
    # topic: <prefix>/led/<target>/set
    local target
    target="${topic#"${prefix}/led/"}"
    target="${target%/set}"

    case "$target" in
      act | pwr | all)
        handle_set "$target" "$payload" "$prefix" || true
        ;;
      *)
        cover_path "led-mqtt:unknown-target"
        log "Ignoring unknown target '$target' (topic: $topic)"
        ;;
    esac
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
