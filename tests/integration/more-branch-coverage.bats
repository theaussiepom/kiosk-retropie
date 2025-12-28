#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
  setup_test_root
}

test_teardown() {
  teardown_test_root
}

@test "branch coverage: healthcheck selection + config/list helper branches" {
  # Provide cover_path + kiosk_retropie_path
  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/lib/common.sh"

  # Config helper branches
  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/lib/config.sh"
  export KIOSK_RETROPIE_CONFIG_ENV="$TEST_ROOT/etc/kiosk-retropie/config.env"
  mkdir -p "$TEST_ROOT/etc/kiosk-retropie"
  echo "FOO=bar" > "$KIOSK_RETROPIE_CONFIG_ENV"
  load_config_env

  unset KIOSK_RETROPIE_CONFIG_ENV
  # missing default config
  load_config_env

  # List helper branches
  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/lib/list.sh"
  run split_list ""
  assert_success
  run split_list "a,b c"
  assert_success
  run in_list "b" "a" "b"
  assert_success
  run in_list "x" "a" "b"
  assert_failure

  # Healthcheck path selection branches
  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/healthcheck.sh"

  # libdir
  local libdir
  libdir="$(mktemp -d)"
  printf '#!/usr/bin/env bash\n' >"$libdir/enter-retro-mode.sh"
  chmod +x "$libdir/enter-retro-mode.sh"
  export KIOSK_RETROPIE_LIBDIR="$libdir"
  run healthcheck_enter_retro_path "$TEST_ROOT/scripts"
  assert_success

  # scriptdir
  KIOSK_RETROPIE_LIBDIR=""
  mkdir -p "$TEST_ROOT/scripts"
  printf '#!/usr/bin/env bash\n' >"$TEST_ROOT/scripts/enter-retro-mode.sh"
  chmod +x "$TEST_ROOT/scripts/enter-retro-mode.sh"
  run healthcheck_enter_retro_path "$TEST_ROOT/scripts"
  assert_success

  # scriptdir/mode
  rm -f "$TEST_ROOT/scripts/enter-retro-mode.sh"
  mkdir -p "$TEST_ROOT/scripts/mode"
  printf '#!/usr/bin/env bash\n' >"$TEST_ROOT/scripts/mode/enter-retro-mode.sh"
  chmod +x "$TEST_ROOT/scripts/mode/enter-retro-mode.sh"
  run healthcheck_enter_retro_path "$TEST_ROOT/scripts"
  assert_success

  # fallback
  rm -f "$TEST_ROOT/scripts/mode/enter-retro-mode.sh"
  run healthcheck_enter_retro_path "$TEST_ROOT/scripts"
  assert_success

  rm -rf "$libdir"
}

@test "branch coverage: enter-retro-mode ledctl selection" {
  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/lib/common.sh"
  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/mode/enter-retro-mode.sh"

  # libdir
  local libdir
  libdir="$(mktemp -d)"
  printf '#!/usr/bin/env bash\n' >"$libdir/ledctl.sh"
  chmod +x "$libdir/ledctl.sh"
  export KIOSK_RETROPIE_LIBDIR="$libdir"
  run kiosk_retropie_ledctl_path "$TEST_ROOT/mode"
  assert_success

  # scriptdir
  KIOSK_RETROPIE_LIBDIR=""
  mkdir -p "$TEST_ROOT/mode"
  printf '#!/usr/bin/env bash\n' >"$TEST_ROOT/mode/ledctl.sh"
  chmod +x "$TEST_ROOT/mode/ledctl.sh"
  run kiosk_retropie_ledctl_path "$TEST_ROOT/mode"
  assert_success

  # scriptdir/../leds
  rm -f "$TEST_ROOT/mode/ledctl.sh"
  mkdir -p "$TEST_ROOT/leds"
  printf '#!/usr/bin/env bash\n' >"$TEST_ROOT/leds/ledctl.sh"
  chmod +x "$TEST_ROOT/leds/ledctl.sh"
  run kiosk_retropie_ledctl_path "$TEST_ROOT/mode"
  assert_success

  # fallback
  rm -f "$TEST_ROOT/leds/ledctl.sh"
  run kiosk_retropie_ledctl_path "$TEST_ROOT/mode"
  assert_success

  rm -rf "$libdir"
}

@test "branch coverage: led-mqtt option/payload/target branches" {
  export KIOSK_RETROPIE_DRY_RUN=1
  export KIOSK_RETROPIE_PATH_COVERAGE=1

  make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub

  export MQTT_HOST="mqtt.local"
  unset MQTT_PORT || true
  unset MQTT_USERNAME || true
  unset MQTT_PASSWORD || true
  unset MQTT_TLS || true

  # Provide a fake, executable ledctl.
  local ledctl="$TEST_ROOT/ledctl.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$ledctl"
  chmod +x "$ledctl"
  export KIOSK_RETROPIE_LEDCTL_PATH="$ledctl"

  source "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"

  # mosq_args: default port/no auth/no tls
  run mosq_args
  assert_success

  # mosq_args: explicit port + auth + tls
  export MQTT_PORT=1884
  export MQTT_USERNAME=u
  export MQTT_PASSWORD=p
  export MQTT_TLS=1
  run mosq_args
  assert_success

  # handle_set: invalid payload
  run handle_set act "maybe" "kiosk-retropie"
  assert_success

  # handle_set: ON single target
  run handle_set act "on" "kiosk-retropie"
  assert_success

  # handle_set: OFF all targets
  run handle_set all "OFF" "kiosk-retropie"
  assert_success

  # handle_set: ledctl missing
  export LEDCTL_PATH="$TEST_ROOT/missing-ledctl.sh"
  run handle_set act on kiosk-retropie
  assert_failure

  # unknown target branch in main
  cat >"$TEST_ROOT/bin/mosquitto_sub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "kiosk-retropie/led/unknown/set on"
exit 0
EOF
  chmod +x "$TEST_ROOT/bin/mosquitto_sub"

  run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"
  assert_success
}
