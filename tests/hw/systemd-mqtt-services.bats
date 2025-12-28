#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"

have_passwordless_sudo() {
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true >/dev/null 2>&1
}

need_root_or_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  have_passwordless_sudo
}

pick_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
PY
}

start_mosquitto() {
  local port="$1"
  local dir="$2"

  local conf="$dir/mosquitto.conf"
  cat >"$conf" <<EOF
persistence false
allow_anonymous true
listener $port 127.0.0.1
EOF

  mosquitto -c "$conf" -v >"$dir/mosquitto.log" 2>&1 &
  echo $! >"$dir/mosquitto.pid"

  local end=$((SECONDS + 10))
  while ((SECONDS < end)); do
    if mosquitto_pub -h 127.0.0.1 -p "$port" -t "test/ping" -m "1" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  return 1
}

stop_pid_file() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 0
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 0
  kill "$pid" 2>/dev/null || true
  sleep 0.2
  kill -9 "$pid" 2>/dev/null || true
}

require_unit_or_skip() {
  local unit="$1"
  if systemctl list-unit-files --no-pager --no-legend "$unit" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${KIOSK_RETROPIE_HW_REQUIRE_UNITS:-0}" == "1" ]]; then
    fail "Required unit not installed on runner: $unit"
  fi
  skip "Unit not installed: $unit"
}

write_dropin() {
  local unit="$1"
  local dropin_name="$2"
  shift 2

  local dir="/run/systemd/system/${unit}.d"
  local file="$dir/$dropin_name"

  sudo -n mkdir -p "$dir"

  # Write file content from stdin.
  sudo -n tee "$file" >/dev/null
}

rm_dropins() {
  local unit="$1"
  sudo -n rm -rf "/run/systemd/system/${unit}.d" >/dev/null 2>&1 || true
}

setup() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "Linux-only systemd tests"
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    skip "systemctl not available"
  fi

  if ! need_root_or_sudo; then
    skip "Need root or passwordless sudo to manage services"
  fi

  if ! command -v mosquitto >/dev/null 2>&1 || ! command -v mosquitto_pub >/dev/null 2>&1 || ! command -v mosquitto_sub >/dev/null 2>&1; then
    skip "mosquitto tooling not installed"
  fi

  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  MQTT_PORT="$(pick_free_port)"
  export MQTT_PORT

  start_mosquitto "$MQTT_PORT" "$TEST_DIR"

  MQTT_HOST=127.0.0.1
  MQTT_TOPIC_PREFIX="kiosk-retropie-systemd-test"
  export MQTT_HOST MQTT_TOPIC_PREFIX
}

teardown() {
  # Best-effort stop services and remove drop-ins.
  sudo -n systemctl stop kiosk-retropie-led-mqtt.service >/dev/null 2>&1 || true
  sudo -n systemctl stop kiosk-retropie-screen-brightness-mqtt.service >/dev/null 2>&1 || true
  sudo -n systemctl stop kiosk-retropie-home-assistant-mqtt.service >/dev/null 2>&1 || true

  rm_dropins kiosk-retropie-led-mqtt.service
  rm_dropins kiosk-retropie-screen-brightness-mqtt.service
  rm_dropins kiosk-retropie-home-assistant-mqtt.service

  sudo -n systemctl daemon-reload >/dev/null 2>&1 || true

  stop_pid_file "$TEST_DIR/mosquitto.pid" || true
  rm -rf "$TEST_DIR" >/dev/null 2>&1 || true
}

@test "systemd: kiosk-retropie-home-assistant-mqtt.service publishes HA discovery and handles commands" {
  require_unit_or_skip kiosk-retropie-home-assistant-mqtt.service

  # Apply drop-in with test broker.
  cat <<EOF | write_dropin kiosk-retropie-home-assistant-mqtt.service ci-test.conf
[Service]
Environment=MQTT_HOME_ASSISTANT_ENABLED=1
Environment=MQTT_HOST=${MQTT_HOST}
Environment=MQTT_PORT=${MQTT_PORT}
Environment=MQTT_TOPIC_PREFIX=${MQTT_TOPIC_PREFIX}
Environment=KIOSK_ENTER_RETRO_PATH=/bin/true
Environment=KIOSK_ENTER_KIOSK_PATH=/bin/true
Environment=KIOSK_SYNC_ROMS_PATH=/bin/true
EOF

  sudo -n systemctl daemon-reload
  sudo -n systemctl restart kiosk-retropie-home-assistant-mqtt.service

  # Give the service time to publish discovery and start its MQTT subscription loop.
  sleep 1

  # Verify a discovery config message is published.
  run mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -C 1 -t "homeassistant/switch/${MQTT_TOPIC_PREFIX}/mode/config"
  assert_success
  assert_regex "$output" '"command_topic"'

  # Verify mode command produces a mode state update.
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$MQTT_TOPIC_PREFIX/mode/set" -m "ON" >/dev/null
  sleep 1
  run mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -C 1 -t "$MQTT_TOPIC_PREFIX/mode/state"
  assert_success
  assert_equal "$output" "ON"

  # Verify rotation command produces a rotation state update.
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$MQTT_TOPIC_PREFIX/screen/rotation/set" -m "left" >/dev/null
  sleep 1
  run mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -C 1 -t "$MQTT_TOPIC_PREFIX/screen/rotation/state"
  assert_success
  assert_equal "$output" "left"
}

@test "systemd: kiosk-retropie-led-mqtt.service starts and responds to MQTT" {
  require_unit_or_skip kiosk-retropie-led-mqtt.service

  if [[ ! -d /sys/class/leds/led-act ]]; then
    skip "ACT LED sysfs not present"
  fi

  # Apply drop-in with test broker.
  cat <<EOF | write_dropin kiosk-retropie-led-mqtt.service ci-test.conf
[Service]
Environment=MQTT_HOST=${MQTT_HOST}
Environment=MQTT_PORT=${MQTT_PORT}
Environment=MQTT_TOPIC_PREFIX=${MQTT_TOPIC_PREFIX}
Environment=MQTT_LED_POLL_SEC=1
EOF

  sudo -n systemctl daemon-reload
  sudo -n systemctl restart kiosk-retropie-led-mqtt.service

  # Toggle via MQTT.
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$MQTT_TOPIC_PREFIX/led/act/set" -m "OFF" >/dev/null

  local end=$((SECONDS + 5))
  local raw=""
  while ((SECONDS < end)); do
    raw="$(tr -d '[:space:]' </sys/class/leds/led-act/brightness 2>/dev/null || true)"
    if [[ "$raw" == "0" ]]; then
      break
    fi
    sleep 0.05
  done
  assert_equal "$raw" "0"

  run mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -C 1 -t "$MQTT_TOPIC_PREFIX/led/act/state"
  assert_success
  assert_equal "$output" "OFF"
}

@test "systemd: kiosk-retropie-screen-brightness-mqtt.service starts and responds to MQTT" {
  require_unit_or_skip kiosk-retropie-screen-brightness-mqtt.service

  local backlight_dir=""
  for d in /sys/class/backlight/*; do
    [[ -d "$d" ]] || continue
    backlight_dir="$d"
    break
  done
  if [[ -z "$backlight_dir" ]]; then
    skip "No /sys/class/backlight device present"
  fi

  # Apply drop-in with test broker.
  cat <<EOF | write_dropin kiosk-retropie-screen-brightness-mqtt.service ci-test.conf
[Service]
Environment=MQTT_HOST=${MQTT_HOST}
Environment=MQTT_PORT=${MQTT_PORT}
Environment=MQTT_TOPIC_PREFIX=${MQTT_TOPIC_PREFIX}
Environment=MQTT_SCREEN_BRIGHTNESS_POLL_SEC=1
Environment=MQTT_SCREEN_BRIGHTNESS_MAX_LOOPS=0
EOF

  sudo -n systemctl daemon-reload
  sudo -n systemctl restart kiosk-retropie-screen-brightness-mqtt.service

  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$MQTT_TOPIC_PREFIX/screen/brightness/set" -m "50" >/dev/null

  # Use script helper to compute percent.
  # shellcheck source=scripts/screen/screen-brightness-mqtt.sh
  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"

  local got
  got="$(read_brightness_percent "$backlight_dir" 2>/dev/null || true)"
  assert_regex "$got" '^[0-9]+$'

  local p="$got"
  if ((p < 45 || p > 55)); then
    fail "Expected ~50%, got: $p"
  fi

  run mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -C 1 -t "$MQTT_TOPIC_PREFIX/screen/brightness/state"
  assert_success
  assert_regex "$output" '^[0-9]+$'
}
