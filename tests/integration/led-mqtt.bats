#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
	export KIOSK_RETROPIE_DRY_RUN=1
}


teardown() {
	teardown_test_root
}

@test "led-mqtt exits 0 when disabled" {
	export KIOSK_LED_MQTT_ENABLED=0
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"
	assert_success
	# Calls may exist due to path coverage markers; ensure we did not subscribe.
	if [[ -f "$TEST_ROOT/calls.log" ]]; then
		! /usr/bin/grep -Fq -- "mosquitto_sub" "$TEST_ROOT/calls.log"
	fi
}

@test "led-mqtt fails if enabled but MQTT_HOST missing" {
	export KIOSK_LED_MQTT_ENABLED=1
	unset MQTT_HOST
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"
	assert_failure
	assert_output --partial "MQTT_HOST is required"
}

@test "led-mqtt records subscribe loop under dry-run" {
	export KIOSK_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"

	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "mosquitto_sub"
}

@test "led-mqtt publishes state via mosquitto_pub under dry-run" {
	export KIOSK_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"

	# Force the script to call publish_state path by invoking internal function
	# via sourcing and calling it directly (entrypoint guard should prevent auto-run).
	make_isolated_path_with_stubs dirname mosquitto_pub
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"
	publish_state "act" "ON" "kiosk-retropie"

	assert_file_contains "$TEST_ROOT/calls.log" "mosquitto_pub"
	assert_file_contains "$TEST_ROOT/calls.log" "kiosk-retropie/led/act/state"
}

@test "led-mqtt mosq_args includes auth + tls options" {
	export KIOSK_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export MQTT_PORT=1884
	export MQTT_USERNAME="u"
	export MQTT_PASSWORD="p"
	export MQTT_TLS=1

	make_isolated_path_with_stubs dirname

	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"
	run mosq_args
	assert_success

	# Avoid relying on bats-assert's multiline matching; just grep tokens.
	/usr/bin/grep -Fq -- "-h" <<<"$output"
	/usr/bin/grep -Fq -- "mqtt.local" <<<"$output"
	/usr/bin/grep -Fq -- "-p" <<<"$output"
	/usr/bin/grep -Fq -- "1884" <<<"$output"
	/usr/bin/grep -Fq -- "-u" <<<"$output"
	/usr/bin/grep -Fq -- "u" <<<"$output"
	/usr/bin/grep -Fq -- "-P" <<<"$output"
	/usr/bin/grep -Fq -- "p" <<<"$output"
	/usr/bin/grep -Fq -- "--tls-version" <<<"$output"
}

@test "led-mqtt handle_set ignores unknown payload" {
	export KIOSK_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"

	# Provide a fake, executable ledctl.
	local ledctl="$TEST_ROOT/ledctl.sh"
	echo '#!/usr/bin/env bash' >"$ledctl"
	echo 'exit 0' >>"$ledctl"
	chmod +x "$ledctl"
	export KIOSK_LEDCTL_PATH="$ledctl"

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"

	run handle_set "act" "bogus" "kiosk-retropie"
	assert_success
}

@test "led-mqtt handle_set fails when ledctl missing" {
	run bash -c '
		set -euo pipefail
		source "$1"
		export KIOSK_RETROPIE_DRY_RUN=1
		export KIOSK_LEDCTL_PATH="$2"
		handle_set act on kiosk-retropie
	' bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh" "$TEST_ROOT/missing-ledctl.sh"
	assert_failure
	assert_output --partial "LED control script missing or not executable"
}

@test "led-mqtt processes a single set message and publishes state (including unknown target)" {
	export KIOSK_LED_MQTT_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	# Provide stubs and override mosquitto_sub to emit one valid and one invalid target.
	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub
	cat >"$TEST_ROOT/bin/mosquitto_sub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "mosquitto_sub $*" >>"${KIOSK_RETROPIE_CALLS_FILE:-/dev/null}" || true

echo "kiosk-retropie/led/all/set on"
echo "kiosk-retropie/led/unknown/set on"
exit 0
EOF
	chmod +x "$TEST_ROOT/bin/mosquitto_sub"

	# Fake ledctl executable (run_cmd will record it because DRY_RUN=1).
	local ledctl="$TEST_ROOT/ledctl.sh"
	echo '#!/usr/bin/env bash' >"$ledctl"
	echo 'exit 0' >>"$ledctl"
	chmod +x "$ledctl"
	export KIOSK_LEDCTL_PATH="$ledctl"

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "mosquitto_sub"
	assert_file_contains "$TEST_ROOT/calls.log" "${ledctl} all on"
	assert_file_contains "$TEST_ROOT/calls.log" "kiosk-retropie/led/act/state"
	assert_file_contains "$TEST_ROOT/calls.log" "kiosk-retropie/led/pwr/state"
}

@test "led-mqtt poller publishes state when LED brightness changes outside MQTT" {
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1
	export KIOSK_LED_MQTT_POLL_SEC=0.05
	export KIOSK_LED_MQTT_MAX_LOOPS=3

	# Create a fake sysfs LED state under KIOSK_RETROPIE_ROOT.
	mkdir -p "$TEST_ROOT/sys/class/leds/ledact" "$TEST_ROOT/sys/class/leds/ledpwr"
	echo 0 >"$TEST_ROOT/sys/class/leds/ledact/brightness"
	echo 0 >"$TEST_ROOT/sys/class/leds/ledpwr/brightness"

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"

	led_state_poller "kiosk-retropie" &
	local poll_pid=$!

	# After the first loop publishes OFF, flip ACT to ON.
	sleep 0.08
	echo 1 >"$TEST_ROOT/sys/class/leds/ledact/brightness"

	wait "$poll_pid"

	assert_file_contains "$TEST_ROOT/calls.log" "-t kiosk-retropie/led/act/state"
	assert_file_contains "$TEST_ROOT/calls.log" "-m OFF"
	assert_file_contains "$TEST_ROOT/calls.log" "-m ON"
}

@test "led-mqtt initial state publish helper covers publish-act/pwr" {
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	mkdir -p "$TEST_ROOT/sys/class/leds/ledact" "$TEST_ROOT/sys/class/leds/ledpwr"
	echo 1 >"$TEST_ROOT/sys/class/leds/ledact/brightness"
	echo 0 >"$TEST_ROOT/sys/class/leds/ledpwr/brightness"

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"

	run publish_led_states_once "kiosk-retropie"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "PATH led-mqtt:state-publish-act"
	assert_file_contains "$TEST_ROOT/calls.log" "PATH led-mqtt:state-publish-pwr"
}

@test "led-mqtt led_state_payload covers invalid target" {
	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"

	run led_state_payload "nope"
	assert_failure
	assert_file_contains "$TEST_ROOT/calls.log" "PATH led-mqtt:state-invalid-target"
}

@test "led-mqtt led_state_payload covers invalid brightness content" {
	# Fake sysfs with invalid brightness.
	mkdir -p "$TEST_ROOT/sys/class/leds/ledact"
	echo "nope" >"$TEST_ROOT/sys/class/leds/ledact/brightness"

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"

	run led_state_payload act
	assert_failure
	assert_file_contains "$TEST_ROOT/calls.log" "PATH led-mqtt:state-brightness-invalid"
}

@test "led-mqtt poller covers max-loops exit" {
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1
	export KIOSK_LED_MQTT_POLL_SEC=0
	export KIOSK_LED_MQTT_MAX_LOOPS=1

	# Fake sysfs so state reads succeed.
	mkdir -p "$TEST_ROOT/sys/class/leds/ledact" "$TEST_ROOT/sys/class/leds/ledpwr"
	echo 0 >"$TEST_ROOT/sys/class/leds/ledact/brightness"
	echo 0 >"$TEST_ROOT/sys/class/leds/ledpwr/brightness"

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/leds/led-mqtt.sh"

	run led_state_poller "kiosk-retropie"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "PATH led-mqtt:state-max-loops"
}
