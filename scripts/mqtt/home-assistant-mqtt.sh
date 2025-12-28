#!/usr/bin/env bash
set -euo pipefail

# Home Assistant MQTT discovery + control bridge.
#
# When enabled, publishes Home Assistant MQTT Discovery config (retained) so HA
# can auto-create entities, and listens for command topics to control the device.
#
# Requires:
#   - mosquitto_sub + mosquitto_pub (package: mosquitto-clients)
#
# Control topics (under <prefix>):
#   <prefix>/mode/set              payload: ON|OFF|RETROPIE|KIOSK
#   <prefix>/mode/state            payload: ON|OFF (retained)
#   <prefix>/roms/sync/press       payload: PRESS
#   <prefix>/screen/rotation/set   payload: normal|left|right|inverted
#   <prefix>/screen/rotation/state payload: normal|left|right|inverted (retained)
#   <prefix>/status                payload: online|offline (retained)
#
# Home Assistant discovery topics (prefix: homeassistant):
#   homeassistant/<component>/<node_id>/<object_id>/config

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
elif [[ -d "$SCRIPT_DIR/../../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../../lib"
else
  echo "kiosk-retropie-home-assistant-mqtt [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

__kiosk_retropie_ha_mqtt_poller_pid=""
__kiosk_retropie_ha_mqtt_sub_pid=""

ha_mqtt_cleanup() {
  # Best-effort offline marker for HA.
  if [[ -n "${MQTT_HOST:-}" ]]; then
    mqtt_publish "$(availability_topic "$(mqtt_topic_prefix)")" "offline" 1 || true
  fi

  if [[ -n "${__kiosk_retropie_ha_mqtt_poller_pid:-}" ]]; then
    kill "${__kiosk_retropie_ha_mqtt_poller_pid}" 2> /dev/null || true
  fi
  if [[ -n "${__kiosk_retropie_ha_mqtt_sub_pid:-}" ]]; then
    kill "${__kiosk_retropie_ha_mqtt_sub_pid}" 2> /dev/null || true
  fi
  exec 3<&- 2> /dev/null || true
}

mosq_args() {
  local args=()

  args+=("-h" "${MQTT_HOST}")
  args+=("-p" "${MQTT_PORT:-1883}")

  if [[ -n "${MQTT_USERNAME:-}" ]]; then
    args+=("-u" "${MQTT_USERNAME}")
  fi
  if [[ -n "${MQTT_PASSWORD:-}" ]]; then
    args+=("-P" "${MQTT_PASSWORD}")
  fi

  if [[ "${MQTT_TLS:-0}" == "1" ]]; then
    args+=("--tls-version" "tlsv1.2")
  fi

  printf '%s\n' "${args[@]}"
}

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

sanitize_id() {
  local s="${1:-}"
  # Keep common HA-safe id chars; map others to '_'.
  s="$(tr -c 'A-Za-z0-9_\-\.' '_' <<< "$s")"
  # Collapse repeated underscores.
  while [[ "$s" == *"__"* ]]; do
    s="${s//__/_}"
  done
  s="${s#_}"
  s="${s%_}"
  printf '%s\n' "$s"
}

default_topic_prefix() {
  if command -v hostname > /dev/null 2>&1; then
    hostname -s 2> /dev/null || hostname 2> /dev/null || printf '%s\n' "kiosk-retropie"
  else
    printf '%s\n' "kiosk-retropie"
  fi
}

mqtt_topic_prefix() {
  printf '%s\n' "${MQTT_TOPIC_PREFIX:-${KIOSK_MQTT_TOPIC_PREFIX:-${KIOSK_RETROPIE_MQTT_TOPIC_PREFIX:-$(default_topic_prefix)}}}"
}

availability_topic() {
  local prefix="$1"
  printf '%s\n' "${prefix}/status"
}

mqtt_publish() {
  local topic="$1"
  local payload="$2"
  local retain="${3:-0}"

  local args=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    args+=("$line")
  done <<< "$(mosq_args)"

  if [[ "$retain" == "1" ]]; then
    run_cmd mosquitto_pub "${args[@]}" -t "$topic" -m "$payload" -r
  else
    run_cmd mosquitto_pub "${args[@]}" -t "$topic" -m "$payload"
  fi
}

ha_discovery_prefix() {
  # Hardcoded to match Home Assistant's MQTT Discovery convention.
  printf '%s\n' "homeassistant"
}

ha_node_id() {
  # Node ID is derived from the device topic prefix.
  sanitize_id "$(mqtt_topic_prefix)"
}

ha_device_json() {
  local node_id="$1"
  local host
  host="$(default_topic_prefix)"

  local name
  name="${MQTT_HOME_ASSISTANT_DEVICE_NAME:-kiosk-retropie-$node_id}"

  printf '{"identifiers":["kiosk-retropie-%s"],"name":"%s","manufacturer":"kiosk-retropie","model":"kiosk-retropie","sw_version":"%s","suggested_area":"%s"}' \
    "$(json_escape "$node_id")" \
    "$(json_escape "$name")" \
    "$(json_escape "${KIOSK_RETROPIE_VERSION:-unknown}")" \
    "$(json_escape "$host")"
}

ha_publish_config() {
  local component="$1"
  local object_id="$2"
  local json_payload="$3"

  local discovery
  discovery="$(ha_discovery_prefix)"
  local node_id
  node_id="$(ha_node_id)"

  local topic
  topic="${discovery}/${component}/${node_id}/${object_id}/config"

  mqtt_publish "$topic" "$json_payload" 1
}

publish_mode_state() {
  local prefix="$1"
  local mode="$2" # kiosk|retropie

  local payload
  case "$mode" in
    retropie) payload="ON" ;;
    kiosk) payload="OFF" ;;
    *) payload="OFF" ;;
  esac

  mqtt_publish "${prefix}/mode/state" "$payload" 1 || true
}

publish_rotation_state() {
  local prefix="$1"
  local rotation="$2"
  mqtt_publish "${prefix}/screen/rotation/state" "$rotation" 1 || true
}

rotation_state_file() {
  kiosk_retropie_path "/run/kiosk-retropie/screen_rotation"
}

read_rotation() {
  local f
  f="$(rotation_state_file)"

  if [[ -f "$f" ]]; then
    tr -d '[:space:]' < "$f" 2> /dev/null || true
    return 0
  fi

  local env_rot="${KIOSK_SCREEN_ROTATION:-${KIOSK_RETROPIE_SCREEN_ROTATION:-}}"
  if [[ -n "$env_rot" ]]; then
    printf '%s\n' "$env_rot"
  else
    printf '%s\n' "normal"
  fi
}

write_rotation() {
  local rotation="$1"
  local f
  f="$(rotation_state_file)"

  run_cmd mkdir -p "$(kiosk_retropie_dirname "$f")"
  if [[ "${KIOSK_RETROPIE_DRY_RUN:-0}" == "1" ]]; then
    record_call "write_rotation $rotation $f"
    return 0
  fi

  printf '%s\n' "$rotation" > "$f"
}

maybe_detect_mode_systemd() {
  if ! command -v systemctl > /dev/null 2>&1; then
    return 1
  fi

  if systemctl is-active --quiet retro-mode.service 2> /dev/null; then
    printf '%s\n' "retropie"
    return 0
  fi

  if systemctl is-active --quiet kiosk.service 2> /dev/null; then
    printf '%s\n' "kiosk"
    return 0
  fi

  return 1
}

mode_state_poller() {
  local prefix="$1"
  local poll_sec="${MQTT_MODE_POLL_SEC:-2}"
  local last=""

  while true; do
    local mode=""
    if mode="$(maybe_detect_mode_systemd)"; then
      :
    else
      mode="${KIOSK_RETROPIE_MODE_STATE:-kiosk}"
    fi

    if [[ "$mode" != "$last" ]]; then
      publish_mode_state "$prefix" "$mode"
      last="$mode"
    fi

    sleep "$poll_sec"
  done
}

publish_config_sensors() {
  local prefix="$1"
  local node_id
  node_id="$(ha_node_id)"

  local availability
  availability="$(availability_topic "$prefix")"

  local dev
  dev="$(ha_device_json "$node_id")"

  # Curated non-sensitive config values.
  local vars=("KIOSK_URL" "NFS_SERVER" "NFS_SAVE_BACKUP_ENABLED" "MQTT_HOST" "MQTT_PORT" "MQTT_TLS" "MQTT_TOPIC_PREFIX" "KIOSK_SCREEN_ROTATION")

  local v
  for v in "${vars[@]}"; do
    # shellcheck disable=SC2154
    local value="${!v:-}"

    local state_topic="${prefix}/config/${v}"
    mqtt_publish "$state_topic" "$value" 1 || true

    local payload
    payload="$(printf '{"name":"%s","state_topic":"%s","entity_category":"diagnostic","availability_topic":"%s","payload_available":"online","payload_not_available":"offline","device":%s}' "$(json_escape "$v")" "$(json_escape "$state_topic")" "$(json_escape "$availability")" "$dev")"

    ha_publish_config "sensor" "config_${v}" "$payload" || true
  done
}

publish_ha_discovery() {
  local prefix="$1"
  local node_id
  node_id="$(ha_node_id)"

  local availability
  availability="$(availability_topic "$prefix")"

  local dev
  dev="$(ha_device_json "$node_id")"

  # Mode switch
  local mode_state="${prefix}/mode/state"
  local mode_cmd="${prefix}/mode/set"
  ha_publish_config "switch" "mode" "$(printf '{"name":"Mode (RetroPie)","state_topic":"%s","command_topic":"%s","payload_on":"ON","payload_off":"OFF","availability_topic":"%s","payload_available":"online","payload_not_available":"offline","device":%s}' \
    "$(json_escape "$mode_state")" \
    "$(json_escape "$mode_cmd")" \
    "$(json_escape "$availability")" \
    "$dev")"

  # ROM sync button
  local sync_cmd="${prefix}/roms/sync/press"
  ha_publish_config "button" "rom_sync" "$(printf '{"name":"ROM sync","command_topic":"%s","payload_press":"PRESS","availability_topic":"%s","payload_available":"online","payload_not_available":"offline","device":%s}' \
    "$(json_escape "$sync_cmd")" \
    "$(json_escape "$availability")" \
    "$dev")"

  # Screen rotation select
  local rot_state="${prefix}/screen/rotation/state"
  local rot_cmd="${prefix}/screen/rotation/set"
  ha_publish_config "select" "screen_rotation" "$(printf '{"name":"Screen rotation","state_topic":"%s","command_topic":"%s","options":["normal","left","right","inverted"],"availability_topic":"%s","payload_available":"online","payload_not_available":"offline","device":%s}' \
    "$(json_escape "$rot_state")" \
    "$(json_escape "$rot_cmd")" \
    "$(json_escape "$availability")" \
    "$dev")"

  # Existing bridges: publish discovery configs that map to the existing topics.
  local act_state="${prefix}/led/act/state"
  local act_cmd="${prefix}/led/act/set"
  ha_publish_config "switch" "led_act" "$(printf '{"name":"LED ACT","state_topic":"%s","command_topic":"%s","payload_on":"ON","payload_off":"OFF","availability_topic":"%s","payload_available":"online","payload_not_available":"offline","device":%s}' \
    "$(json_escape "$act_state")" \
    "$(json_escape "$act_cmd")" \
    "$(json_escape "$availability")" \
    "$dev")"

  local pwr_state="${prefix}/led/pwr/state"
  local pwr_cmd="${prefix}/led/pwr/set"
  ha_publish_config "switch" "led_pwr" "$(printf '{"name":"LED PWR","state_topic":"%s","command_topic":"%s","payload_on":"ON","payload_off":"OFF","availability_topic":"%s","payload_available":"online","payload_not_available":"offline","device":%s}' \
    "$(json_escape "$pwr_state")" \
    "$(json_escape "$pwr_cmd")" \
    "$(json_escape "$availability")" \
    "$dev")"

  local b_state="${prefix}/screen/brightness/state"
  local b_cmd="${prefix}/screen/brightness/set"
  ha_publish_config "number" "screen_brightness" "$(printf '{"name":"Screen brightness","state_topic":"%s","command_topic":"%s","min":0,"max":100,"mode":"slider","availability_topic":"%s","payload_available":"online","payload_not_available":"offline","device":%s}' \
    "$(json_escape "$b_state")" \
    "$(json_escape "$b_cmd")" \
    "$(json_escape "$availability")" \
    "$dev")"
}

handle_mode_set() {
  local payload_raw="$1"
  local prefix="$2"

  local payload
  payload="$(tr '[:lower:]' '[:upper:]' <<< "$payload_raw" | tr -d '[:space:]')"

  local target=""
  case "$payload" in
    ON | RETROPIE)
      target="retropie"
      ;;
    OFF | KIOSK)
      target="kiosk"
      ;;
    *)
      log "Ignoring mode payload '$payload_raw'"
      return 0
      ;;
  esac

  if [[ "$target" == "retropie" ]]; then
    local enter="${KIOSK_ENTER_RETRO_PATH:-${KIOSK_RETROPIE_LIBDIR:-$(kiosk_retropie_path /usr/local/lib/kiosk-retropie)}/enter-retro-mode.sh}"
    if [[ ! -x "$enter" ]]; then
      die "enter-retro-mode.sh missing or not executable: $enter"
    fi
    run_cmd "$enter"
  else
    local enter="${KIOSK_ENTER_KIOSK_PATH:-${KIOSK_RETROPIE_LIBDIR:-$(kiosk_retropie_path /usr/local/lib/kiosk-retropie)}/enter-kiosk-mode.sh}"
    if [[ ! -x "$enter" ]]; then
      die "enter-kiosk-mode.sh missing or not executable: $enter"
    fi
    run_cmd "$enter"
  fi

  export KIOSK_RETROPIE_MODE_STATE="$target"
  publish_mode_state "$prefix" "$target"
}

handle_rom_sync_press() {
  local payload_raw="$1"

  local payload
  payload="$(tr '[:lower:]' '[:upper:]' <<< "$payload_raw" | tr -d '[:space:]')"

  if [[ "$payload" != "PRESS" && -n "$payload" ]]; then
    log "Ignoring ROM sync payload '$payload_raw'"
    return 0
  fi

  local sync="${KIOSK_SYNC_ROMS_PATH:-${KIOSK_RETROPIE_LIBDIR:-$(kiosk_retropie_path /usr/local/lib/kiosk-retropie)}/sync-roms.sh}"
  if [[ -x "$sync" ]]; then
    run_cmd "$sync"
    return 0
  fi

  if command -v systemctl > /dev/null 2>&1; then
    run_cmd systemctl start boot-sync.service || true
  fi
}

handle_rotation_set() {
  local payload_raw="$1"
  local prefix="$2"

  local payload
  payload="$(tr '[:upper:]' '[:lower:]' <<< "$payload_raw" | tr -d '[:space:]')"

  case "$payload" in
    normal | left | right | inverted) : ;;
    *)
      log "Ignoring rotation payload '$payload_raw'"
      return 0
      ;;
  esac

  write_rotation "$payload"
  publish_rotation_state "$prefix" "$payload"

  # Best-effort live apply (may fail if no X session is available).
  if command -v xrandr > /dev/null 2>&1; then
    xrandr -o "$payload" > /dev/null 2>&1 || true
  fi
}

main() {
  export KIOSK_RETROPIE_LOG_PREFIX="kiosk-retropie-home-assistant-mqtt"

  if [[ "${MQTT_HOME_ASSISTANT_ENABLED:-${MQTT_HOME_ASSISTANT:-0}}" != "1" ]]; then
    log "MQTT_HOME_ASSISTANT_ENABLED!=1; exiting (disabled)."
    exit 0
  fi

  if [[ -z "${MQTT_HOST:-}" ]]; then
    die "MQTT_HOST is required"
  fi

  local prefix
  prefix="$(mqtt_topic_prefix)"

  # Publish online marker.
  mqtt_publish "$(availability_topic "$prefix")" "online" 1

  # Publish discovery config.
  publish_ha_discovery "$prefix"
  publish_config_sensors "$prefix"

  # Publish initial state.
  export KIOSK_RETROPIE_MODE_STATE="${KIOSK_RETROPIE_MODE_STATE:-kiosk}"
  publish_mode_state "$prefix" "${KIOSK_RETROPIE_MODE_STATE}"

  local rot
  rot="$(read_rotation)"
  publish_rotation_state "$prefix" "$rot"

  # Background poller for mode state.
  mode_state_poller "$prefix" &
  __kiosk_retropie_ha_mqtt_poller_pid=$!

  local args=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    args+=("$line")
  done <<< "$(mosq_args)"

  local mode_cmd="${prefix}/mode/set"
  local sync_cmd="${prefix}/roms/sync/press"
  local rot_cmd="${prefix}/screen/rotation/set"

  log "Subscribing to ${mode_cmd}, ${sync_cmd}, ${rot_cmd}"

  exec 3< <(mosquitto_sub "${args[@]}" -v -t "$mode_cmd" -t "$sync_cmd" -t "$rot_cmd")
  __kiosk_retropie_ha_mqtt_sub_pid=$!

  trap ha_mqtt_cleanup EXIT INT TERM

  while read -r topic payload <&3; do
    case "$topic" in
      */mode/set)
        handle_mode_set "$payload" "$prefix" || true
        ;;
      */roms/sync/press)
        handle_rom_sync_press "$payload" || true
        ;;
      */screen/rotation/set)
        handle_rotation_set "$payload" "$prefix" || true
        ;;
      *)
        log "Ignoring unknown topic '$topic'"
        ;;
    esac
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
