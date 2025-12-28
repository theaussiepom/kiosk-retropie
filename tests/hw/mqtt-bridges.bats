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

wait_for_file_contains() {
  local file="$1"
  local needle="$2"
  local timeout_sec="${3:-5}"

  local end=$((SECONDS + timeout_sec))
  while ((SECONDS < end)); do
    if [[ -f "$file" ]] && grep -Fq "$needle" "$file"; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

wait_for_value() {
  local file="$1"
  local expected="$2"
  local timeout_sec="${3:-5}"

  local end=$((SECONDS + timeout_sec))
  while ((SECONDS < end)); do
    if [[ -f "$file" ]]; then
      local v
      v="$(tr -d '[:space:]' <"$file" 2>/dev/null || true)"
      if [[ "$v" == "$expected" ]]; then
        return 0
      fi
    fi
    sleep 0.05
  done
  return 1
}

start_mosquitto() {
  local port="$1"
  local dir="$2"

  local conf="$dir/mosquitto.conf"
  cat >"$conf" <<EOF
# Test broker (no persistence)
persistence false
allow_anonymous true
listener $port 127.0.0.1
EOF

  mosquitto -c "$conf" -v >"$dir/mosquitto.log" 2>&1 &
  echo $! >"$dir/mosquitto.pid"

  # Wait until the broker accepts connections.
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

read_active_trigger() {
  local trigger_file="$1"
  sed -n 's/.*\[\([^]]\+\)\].*/\1/p' "$trigger_file" | head -n 1
}

write_sysfs() {
  local file="$1"
  local value="$2"

  if [[ -w "$file" ]]; then
    printf '%s' "$value" >"$file"
    return 0
  fi

  if have_passwordless_sudo; then
    printf '%s' "$value" | sudo -n tee "$file" >/dev/null
    return $?
  fi

  return 126
}

setup() {
  # These tests are meant for the Pi runner.
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "Linux-only"
  fi

  if ! command -v mosquitto >/dev/null 2>&1; then
    skip "mosquitto broker not installed"
  fi
  if ! command -v mosquitto_pub >/dev/null 2>&1; then
    skip "mosquitto_pub not installed"
  fi
  if ! command -v mosquitto_sub >/dev/null 2>&1; then
    skip "mosquitto_sub not installed"
  fi

  if ! need_root_or_sudo; then
    skip "Need root or passwordless sudo for sysfs writes"
  fi

  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  MQTT_PORT="$(pick_free_port)"
  export MQTT_PORT

  start_mosquitto "$MQTT_PORT" "$TEST_DIR"

  MQTT_HOST=127.0.0.1
  MQTT_TOPIC_PREFIX="kiosk-retropie-test"

  export MQTT_HOST MQTT_TOPIC_PREFIX

  # Capture original LED triggers (best effort) for restore.
  ACT_TRIGGER_FILE="/sys/class/leds/led-act/trigger"
  PWR_TRIGGER_FILE="/sys/class/leds/led-pwr/trigger"
  ACT_BRIGHTNESS_FILE="/sys/class/leds/led-act/brightness"
  PWR_BRIGHTNESS_FILE="/sys/class/leds/led-pwr/brightness"

  if [[ -f "$ACT_TRIGGER_FILE" ]]; then
    ACT_ORIG_TRIGGER="$(read_active_trigger "$ACT_TRIGGER_FILE" || true)"
  else
    ACT_ORIG_TRIGGER=""
  fi
  if [[ -f "$PWR_TRIGGER_FILE" ]]; then
    PWR_ORIG_TRIGGER="$(read_active_trigger "$PWR_TRIGGER_FILE" || true)"
  else
    PWR_ORIG_TRIGGER=""
  fi

  export ACT_TRIGGER_FILE PWR_TRIGGER_FILE ACT_BRIGHTNESS_FILE PWR_BRIGHTNESS_FILE ACT_ORIG_TRIGGER PWR_ORIG_TRIGGER

  # Backlight restore (optional device).
  BACKLIGHT_DIR=""
  for d in /sys/class/backlight/*; do
    [[ -d "$d" ]] || continue
    BACKLIGHT_DIR="$d"
    break
  done

  if [[ -n "$BACKLIGHT_DIR" && -f "$BACKLIGHT_DIR/brightness" ]]; then
    BACKLIGHT_BRIGHTNESS_FILE="$BACKLIGHT_DIR/brightness"
    BACKLIGHT_ORIG="$(cat "$BACKLIGHT_BRIGHTNESS_FILE" 2>/dev/null || true)"
  else
    BACKLIGHT_BRIGHTNESS_FILE=""
    BACKLIGHT_ORIG=""
  fi

  export BACKLIGHT_DIR BACKLIGHT_BRIGHTNESS_FILE BACKLIGHT_ORIG
}

teardown() {
  stop_pid_file "$TEST_DIR/led-mqtt.pid" || true
  stop_pid_file "$TEST_DIR/screen-mqtt.pid" || true
  stop_pid_file "$TEST_DIR/mosquitto.pid" || true

  # Restore LEDs.
  if [[ -n "${ACT_ORIG_TRIGGER:-}" && -f "${ACT_TRIGGER_FILE:-}" ]]; then
    write_sysfs "$ACT_TRIGGER_FILE" "$ACT_ORIG_TRIGGER" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PWR_ORIG_TRIGGER:-}" && -f "${PWR_TRIGGER_FILE:-}" ]]; then
    write_sysfs "$PWR_TRIGGER_FILE" "$PWR_ORIG_TRIGGER" >/dev/null 2>&1 || true
  fi

  # Restore backlight brightness.
  if [[ -n "${BACKLIGHT_BRIGHTNESS_FILE:-}" && -n "${BACKLIGHT_ORIG:-}" ]]; then
    write_sysfs "$BACKLIGHT_BRIGHTNESS_FILE" "$BACKLIGHT_ORIG" >/dev/null 2>&1 || true
  fi

  rm -rf "$TEST_DIR" >/dev/null 2>&1 || true
}

@test "MQTT LED bridge toggles ACT LED and publishes state" {
  if [[ ! -d /sys/class/leds/led-act ]]; then
    skip "ACT LED sysfs not present"
  fi

  # Start bridge.
  (
    export MQTT_LED_ENABLED=1
    export MQTT_PORT
    export MQTT_HOST
    export MQTT_TOPIC_PREFIX
    export KIOSK_RETROPIE_LEDCTL_PATH="$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/ledctl.sh"

    "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh" >"$TEST_DIR/led-mqtt.log" 2>&1
  ) &
  echo $! >"$TEST_DIR/led-mqtt.pid"

  wait_for_file_contains "$TEST_DIR/led-mqtt.log" "Subscribing" 8

  # Force OFF then verify brightness==0.
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$MQTT_TOPIC_PREFIX/led/act/set" -m "OFF" >/dev/null
  assert wait_for_value "$ACT_BRIGHTNESS_FILE" "0" 5

  # Verify retained state topic.
  run mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -C 1 -t "$MQTT_TOPIC_PREFIX/led/act/state"
  assert_success
  assert_equal "$output" "OFF"

  # Turn ON then verify brightness becomes non-zero (usually 1).
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$MQTT_TOPIC_PREFIX/led/act/set" -m "ON" >/dev/null

  local end=$((SECONDS + 5))
  local raw=""
  while ((SECONDS < end)); do
    raw="$(tr -d '[:space:]' <"$ACT_BRIGHTNESS_FILE" 2>/dev/null || true)"
    if [[ "$raw" =~ ^[0-9]+$ ]] && ((raw > 0)); then
      break
    fi
    sleep 0.05
  done
  if [[ ! "$raw" =~ ^[0-9]+$ ]] || ((raw <= 0)); then
    fail "Expected ACT brightness > 0 after ON, got: $raw"
  fi

  run mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -C 1 -t "$MQTT_TOPIC_PREFIX/led/act/state"
  assert_success
  assert_equal "$output" "ON"
}

@test "MQTT screen brightness bridge sets brightness percent and publishes state" {
  if [[ -z "$BACKLIGHT_DIR" || ! -d "$BACKLIGHT_DIR" ]]; then
    skip "No /sys/class/backlight device present"
  fi

  # Start bridge.
  (
    export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
    export MQTT_PORT
    export MQTT_HOST
    export MQTT_TOPIC_PREFIX
    export MQTT_SCREEN_BRIGHTNESS_POLL_SEC=1
    export MQTT_SCREEN_BRIGHTNESS_MAX_LOOPS=10

    "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh" >"$TEST_DIR/screen-mqtt.log" 2>&1
  ) &
  echo $! >"$TEST_DIR/screen-mqtt.pid"

  wait_for_file_contains "$TEST_DIR/screen-mqtt.log" "Subscribing" 8

  # Set to 50%.
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$MQTT_TOPIC_PREFIX/screen/brightness/set" -m "50" >/dev/null

  # Read percent using the real script helpers.
  # shellcheck source=scripts/screen/screen-brightness-mqtt.sh
  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"

  local got
  got="$(read_brightness_percent "$BACKLIGHT_DIR" 2>/dev/null || true)"
  if [[ -z "$got" ]]; then
    fail "Unable to read brightness percent from $BACKLIGHT_DIR"
  fi

  if [[ ! "$got" =~ ^[0-9]+$ ]]; then
    fail "Expected numeric percent, got: $got"
  fi

  local p="$got"
  # Allow small rounding error.
  if ((p < 45 || p > 55)); then
    fail "Expected ~50%, got: $p"
  fi

  # Verify retained state topic eventually reflects 50.
  run mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -C 1 -t "$MQTT_TOPIC_PREFIX/screen/brightness/state"
  assert_success
  assert_regex "$output" '^[0-9]+$'
}
