#!/usr/bin/env bats

load 'vendor/bats-support/load'
load 'vendor/bats-assert/load'
load 'helpers/common'

setup() {
	setup_test_root
	export RETRO_HA_DRY_RUN=1
}


teardown() {
	teardown_test_root
}

@test "led-mqtt exits 0 when disabled" {
	export RETRO_HA_LED_MQTT_ENABLED=0
	run bash "$BATS_TEST_DIRNAME/../scripts/leds/led-mqtt.sh"
	assert_success
	# Calls may exist due to path coverage markers; ensure we did not subscribe.
	if [[ -f "$TEST_ROOT/calls.log" ]]; then
		! /usr/bin/grep -Fq -- "mosquitto_sub" "$TEST_ROOT/calls.log"
	fi
}

@test "led-mqtt fails if enabled but MQTT_HOST missing" {
	export RETRO_HA_LED_MQTT_ENABLED=1
	unset MQTT_HOST
	run bash "$BATS_TEST_DIRNAME/../scripts/leds/led-mqtt.sh"
	assert_failure
	assert_output --partial "MQTT_HOST is required"
}

@test "led-mqtt records subscribe loop under dry-run" {
	export RETRO_HA_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"

	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub

	run bash "$BATS_TEST_DIRNAME/../scripts/leds/led-mqtt.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "mosquitto_sub"
}

@test "led-mqtt publishes state via mosquitto_pub under dry-run" {
	export RETRO_HA_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"

	# Force the script to call publish_state path by invoking internal function
	# via sourcing and calling it directly (entrypoint guard should prevent auto-run).
	make_isolated_path_with_stubs dirname mosquitto_pub
	source "$BATS_TEST_DIRNAME/../scripts/leds/led-mqtt.sh"
	publish_state "act" "ON" "retro-ha"

	assert_file_contains "$TEST_ROOT/calls.log" "mosquitto_pub"
	assert_file_contains "$TEST_ROOT/calls.log" "retro-ha/led/act/state"
}

@test "led-mqtt mosq_args includes auth + tls options" {
	export RETRO_HA_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export MQTT_PORT=1884
	export MQTT_USERNAME="u"
	export MQTT_PASSWORD="p"
	export MQTT_TLS=1

	make_isolated_path_with_stubs dirname

	source "$BATS_TEST_DIRNAME/../scripts/leds/led-mqtt.sh"
	run mosq_args
	assert_success
	assert_output --partial "-h"
	assert_output --partial "mqtt.local"
	assert_output --partial "-p"
	assert_output --partial "1884"
	assert_output --partial "-u"
	assert_output --partial "u"
	assert_output --partial "-P"
	assert_output --partial "p"
	assert_output --partial "--tls-version"
}

@test "led-mqtt handle_set ignores unknown payload" {
	export RETRO_HA_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"

	# Provide a fake, executable ledctl.
	local ledctl="$TEST_ROOT/ledctl.sh"
	echo '#!/usr/bin/env bash' >"$ledctl"
	echo 'exit 0' >>"$ledctl"
	chmod +x "$ledctl"
	export RETRO_HA_LEDCTL_PATH="$ledctl"

	make_isolated_path_with_stubs dirname
	source "$BATS_TEST_DIRNAME/../scripts/leds/led-mqtt.sh"

	run handle_set "act" "bogus" "retro-ha"
	assert_success
}

@test "led-mqtt handle_set fails when ledctl missing" {
	run bash -c '
		set -euo pipefail
		source "$1"
		export RETRO_HA_DRY_RUN=1
		export RETRO_HA_LEDCTL_PATH="$2"
		handle_set act on retro-ha
	' bash "$BATS_TEST_DIRNAME/../scripts/leds/led-mqtt.sh" "$TEST_ROOT/missing-ledctl.sh"
	assert_failure
	assert_output --partial "LED control script missing or not executable"
}

@test "led-mqtt processes a single set message and publishes state (including unknown target)" {
	export RETRO_HA_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export RETRO_HA_DRY_RUN=1

	# Provide stubs and override mosquitto_sub to emit one valid and one invalid target.
	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub
	cat >"$TEST_ROOT/bin/mosquitto_sub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "mosquitto_sub $*" >>"${RETRO_HA_CALLS_FILE:-/dev/null}" || true

echo "retro-ha/led/all/set on"
echo "retro-ha/led/unknown/set on"
exit 0
EOF
	chmod +x "$TEST_ROOT/bin/mosquitto_sub"

	# Fake ledctl executable (run_cmd will record it because DRY_RUN=1).
	local ledctl="$TEST_ROOT/ledctl.sh"
	echo '#!/usr/bin/env bash' >"$ledctl"
	echo 'exit 0' >>"$ledctl"
	chmod +x "$ledctl"
	export RETRO_HA_LEDCTL_PATH="$ledctl"

	run bash "$BATS_TEST_DIRNAME/../scripts/leds/led-mqtt.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "mosquitto_sub"
	assert_file_contains "$TEST_ROOT/calls.log" "${ledctl} all on"
	assert_file_contains "$TEST_ROOT/calls.log" "retro-ha/led/act/state"
	assert_file_contains "$TEST_ROOT/calls.log" "retro-ha/led/pwr/state"
}
