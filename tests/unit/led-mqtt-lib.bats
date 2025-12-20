#!/usr/bin/env bats

load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-support/load"
load "${RETRO_HA_REPO_ROOT}/tests/vendor/bats-assert/load"

setup() {
  export RETRO_HA_ROOT
  RETRO_HA_ROOT="$(mktemp -d)"

  export RETRO_HA_CALLS_FILE
  RETRO_HA_CALLS_FILE="${RETRO_HA_ROOT}/calls.txt"

  export RETRO_HA_CALLS_FILE_APPEND=""
  export RETRO_HA_DRY_RUN=1

  # Provide an executable LEDCTL stub and force the script to use it.
  export RETRO_HA_LEDCTL_PATH
  RETRO_HA_LEDCTL_PATH="${RETRO_HA_ROOT}/ledctl.sh"
  printf '#!/usr/bin/env bash\necho ledctl "$@"\n' >"$RETRO_HA_LEDCTL_PATH"
  chmod +x "$RETRO_HA_LEDCTL_PATH"

  export MQTT_HOST="broker"
  unset MQTT_PORT || true
  unset MQTT_USERNAME || true
  unset MQTT_PASSWORD || true
  unset MQTT_TLS || true

  # Source the script under test (guarded main).
  source "${RETRO_HA_REPO_ROOT}/scripts/leds/led-mqtt.sh"
}

test_teardown() {
  rm -rf "${RETRO_HA_ROOT}" || true
}

@test "mosq_args emits minimal required args" {
  run mosq_args
  assert_success
  assert_output $'-h\nbroker\n-p\n1883'
}

@test "mosq_args includes optional auth and tls" {
  MQTT_PORT=1999
  MQTT_USERNAME="u"
  MQTT_PASSWORD="p"
  MQTT_TLS=1

  run mosq_args
  assert_success
  assert_output $'-h\nbroker\n-p\n1999\n-u\nu\n-P\np\n--tls-version\ntlsv1.2'
}

@test "handle_set ignores unknown payload" {
  run handle_set act "maybe" "retro-ha"
  assert_success

  # Ignore PATH coverage lines; ensure there were no side-effect calls.
  run bash -c '
    set -euo pipefail
    f="$1"
    if [[ ! -f "$f" ]]; then
      exit 0
    fi
    non_path=$(grep -v "^PATH " "$f" || true)
    [[ -z "$non_path" ]]
  ' bash "$RETRO_HA_CALLS_FILE"
  assert_success
}

@test "handle_set runs ledctl and publishes state for act" {
  run handle_set act "on" "retro-ha"
  assert_success

  run bash -c 'grep -v "^PATH " "$1"' bash "$RETRO_HA_CALLS_FILE"
  assert_success

  local expected
  expected="${RETRO_HA_LEDCTL_PATH} act on"$'\n'"mosquitto_pub -h broker -p 1883 -t retro-ha/led/act/state -m ON -r"
  assert_output "$expected"
}

@test "handle_set publishes both states for all" {
  run handle_set all "OFF" "retro-ha"
  assert_success

  run bash -c 'grep -v "^PATH " "$1"' bash "$RETRO_HA_CALLS_FILE"
  assert_success

  local expected
  expected="${RETRO_HA_LEDCTL_PATH} all off"$'\n'"mosquitto_pub -h broker -p 1883 -t retro-ha/led/act/state -m OFF -r"$'\n'"mosquitto_pub -h broker -p 1883 -t retro-ha/led/pwr/state -m OFF -r"
  assert_output "$expected"
}
