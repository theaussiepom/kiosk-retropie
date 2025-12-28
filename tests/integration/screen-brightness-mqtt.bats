#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
}

teardown() {
	teardown_test_root
}

write_mosquitto_sub_stub() {
	local line="${1:-}"

	cat >"$TEST_ROOT/bin/mosquitto_sub" <<EOF
#!/usr/bin/env bash
set -euo pipefail

echo "mosquitto_sub \$*" >>"\${KIOSK_RETROPIE_CALLS_FILE:-/dev/null}" || true

if [[ -n "${line}" ]]; then
	echo "${line}"
fi

exit 0
EOF
	chmod +x "$TEST_ROOT/bin/mosquitto_sub"
}

make_fake_backlight() {
	local name="$1"
	local max="$2"
	local initial="$3"

	local d
	d="$TEST_ROOT/sys/class/backlight/$name"
	mkdir -p "$d"
	echo "$max" >"$d/max_brightness"
	echo "$initial" >"$d/brightness"
}

@test "screen-brightness-mqtt exits 0 when disabled" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=0
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_success
	if [[ -f "$TEST_ROOT/calls.log" ]]; then
		! /usr/bin/grep -Fq -- "mosquitto_sub" "$TEST_ROOT/calls.log"
	fi
}

@test "screen-brightness-mqtt fails if enabled but MQTT_HOST missing" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	unset MQTT_HOST
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_failure
	assert_output --partial "MQTT_HOST is required"
}

@test "screen-brightness-mqtt records subscribe under dry-run" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "mosquitto_sub"
}

@test "screen-brightness-mqtt processes a set message, writes brightness, and publishes retained state" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=0

	# Create a fake sysfs backlight under KIOSK_RETROPIE_ROOT.
	make_fake_backlight "test" "200" "0"

	# Provide stubs and override mosquitto_sub to emit one set message.
	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub
	cat >"$TEST_ROOT/bin/mosquitto_sub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "mosquitto_sub $*" >>"${KIOSK_RETROPIE_CALLS_FILE:-/dev/null}" || true

echo "kiosk-retropie/screen/brightness/set 50"
exit 0
EOF
	chmod +x "$TEST_ROOT/bin/mosquitto_sub"

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_success

	# 50% of max(200) => 100
	run cat "$TEST_ROOT/sys/class/backlight/test/brightness"
	assert_success
	assert_output "100"

	assert_file_contains "$TEST_ROOT/calls.log" "mosquitto_pub"
	assert_file_contains "$TEST_ROOT/calls.log" "kiosk-retropie/screen/brightness/state"
	assert_file_contains "$TEST_ROOT/calls.log" "-m 50"
	assert_file_contains "$TEST_ROOT/calls.log" "-r"
}

@test "screen-brightness-mqtt prefers <script_dir>/lib when present" {
	# Cover the LIB_DIR="$SCRIPT_DIR/lib" branch under kcov by creating a
	# temporary lib/ symlink next to the script.
	local lib_link="$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/lib"
	rm -f "$lib_link"
	ln -s ../lib "$lib_link"

	export MQTT_SCREEN_BRIGHTNESS_ENABLED=0
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	rm -f "$lib_link"
	assert_success
}

@test "screen-brightness-mqtt fails fast when scripts/lib cannot be located" {
	run bash -c '
		set -euo pipefail
		repo="$1"
		backup="$2"

		rm -f "$repo/scripts/screen/lib" || true
		mv "$repo/scripts/lib" "$backup"
		trap "mv \"$backup\" \"$repo/scripts/lib\" 2>/dev/null || true" EXIT

		export MQTT_SCREEN_BRIGHTNESS_ENABLED=0
		bash "$repo/scripts/screen/screen-brightness-mqtt.sh"
	' bash "$KIOSK_RETROPIE_REPO_ROOT" "$TEST_ROOT/scripts-lib-backup"
	assert_failure
	assert_output --partial "unable to locate scripts/lib"
}

@test "screen-brightness-mqtt covers max-missing on initial publish" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	local d
	d="$TEST_ROOT/sys/class/backlight/test"
	mkdir -p "$d"
	echo 0 >"$d/brightness"
	# no max_brightness

	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub
	write_mosquitto_sub_stub ""

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_success
}

@test "screen-brightness-mqtt covers max-invalid on initial publish" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	local d
	d="$TEST_ROOT/sys/class/backlight/test"
	mkdir -p "$d"
	echo 0 >"$d/brightness"
	echo 0 >"$d/max_brightness"

	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub
	write_mosquitto_sub_stub ""

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_success
}

@test "screen-brightness-mqtt clamps percent to 100 when raw exceeds max" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	make_fake_backlight "test" "100" "1000"

	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub
	write_mosquitto_sub_stub ""

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "-m 100"
}

@test "screen-brightness-mqtt ignores out-of-range payload (101)" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	make_fake_backlight "test" "100" "0"

	make_isolated_path_with_stubs dirname mosquitto_sub mosquitto_pub
	write_mosquitto_sub_stub "kiosk-retropie/screen/brightness/set 101"

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_success
}

@test "screen-brightness-mqtt mosq_args includes auth + tls options" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export MQTT_PORT=1884
	export MQTT_USERNAME="u"
	export MQTT_PASSWORD="p"
	export MQTT_TLS=1

	make_isolated_path_with_stubs dirname

	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	run mosq_args
	assert_success

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

@test "screen-brightness-mqtt uses backlight auto selection when name not set" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	make_fake_backlight "auto0" "100" "0"

	make_isolated_path_with_stubs dirname mosquitto_pub
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"

	run handle_set "50" "kiosk-retropie"
	assert_success

	# Dry-run write path should record the write call.
	assert_file_contains "$TEST_ROOT/calls.log" "write_brightness"
}

@test "screen-brightness-mqtt fails when no backlight exists" {
	run bash -c '
		set -euo pipefail
		export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
		export MQTT_HOST="mqtt.local"
		export KIOSK_RETROPIE_DRY_RUN=1
		source "$1"
		handle_set 50 kiosk-retropie
	' bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_failure
}

@test "screen-brightness-mqtt fails when max_brightness missing" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	local d
	d="$TEST_ROOT/sys/class/backlight/test"
	mkdir -p "$d"
	echo 0 >"$d/brightness"
	# no max_brightness

	run bash -c 'set -euo pipefail; source "$1"; handle_set 50 kiosk-retropie' bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_failure
}

@test "screen-brightness-mqtt fails when max_brightness invalid" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	local d
	d="$TEST_ROOT/sys/class/backlight/test"
	mkdir -p "$d"
	echo 0 >"$d/brightness"
	echo 0 >"$d/max_brightness"

	run bash -c 'set -euo pipefail; source "$1"; handle_set 50 kiosk-retropie' bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"
	assert_failure
}

@test "screen-brightness-mqtt ignores invalid payload" {
	export MQTT_SCREEN_BRIGHTNESS_ENABLED=1
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	make_fake_backlight "test" "255" "10"

	make_isolated_path_with_stubs dirname mosquitto_pub
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"

	run handle_set "not-a-number" "kiosk-retropie"
	assert_success
}

@test "screen-brightness-mqtt poller publishes state when brightness changes outside MQTT" {
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1
	export MQTT_SCREEN_BRIGHTNESS_POLL_SEC=0.05
	export MQTT_SCREEN_BRIGHTNESS_MAX_LOOPS=3

	# Create a fake sysfs backlight under KIOSK_RETROPIE_ROOT.
	make_fake_backlight "test" "100" "0"

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"

	brightness_state_poller "kiosk-retropie" &
	local poll_pid=$!

	# Wait until the first loop publishes 0, then flip to 50.
	local saw_zero=0
	for _ in {1..50}; do
		if [[ -f "$TEST_ROOT/calls.log" ]] && grep -Fq -- "-m 0" "$TEST_ROOT/calls.log"; then
			saw_zero=1
			break
		fi
		sleep 0.02
	done
	[[ "$saw_zero" == "1" ]]

	echo 50 >"$TEST_ROOT/sys/class/backlight/test/brightness"

	wait "$poll_pid"

	assert_file_contains "$TEST_ROOT/calls.log" "-t kiosk-retropie/screen/brightness/state"
	assert_file_contains "$TEST_ROOT/calls.log" "-m 0"
	assert_file_contains "$TEST_ROOT/calls.log" "-m 50"
}

@test "screen-brightness-mqtt initial state publish helper covers state-publish" {
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1

	make_fake_backlight "test" "100" "20"

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"

	run publish_brightness_state_once "kiosk-retropie"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "PATH screen-brightness-mqtt:state-publish"
}

@test "screen-brightness-mqtt read_brightness_percent covers missing brightness file" {
	local d
	d="$TEST_ROOT/sys/class/backlight/test"
	mkdir -p "$d"
	echo 100 >"$d/max_brightness"
	# brightness intentionally missing

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"

	run read_brightness_percent "$d"
	assert_failure
	assert_file_contains "$TEST_ROOT/calls.log" "PATH screen-brightness-mqtt:read-missing"
}

@test "screen-brightness-mqtt read_brightness_percent covers invalid brightness content" {
	local d
	d="$TEST_ROOT/sys/class/backlight/test"
	mkdir -p "$d"
	echo 100 >"$d/max_brightness"
	echo nope >"$d/brightness"

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"

	run read_brightness_percent "$d"
	assert_failure
	assert_file_contains "$TEST_ROOT/calls.log" "PATH screen-brightness-mqtt:read-invalid"
}

@test "screen-brightness-mqtt poller covers max-loops exit" {
	export MQTT_HOST="mqtt.local"
	export KIOSK_RETROPIE_DRY_RUN=1
	export MQTT_SCREEN_BRIGHTNESS_POLL_SEC=0
	export MQTT_SCREEN_BRIGHTNESS_MAX_LOOPS=1

	make_fake_backlight "test" "100" "0"

	make_isolated_path_with_stubs dirname
	source "$KIOSK_RETROPIE_REPO_ROOT/scripts/screen/screen-brightness-mqtt.sh"

	run brightness_state_poller "kiosk-retropie"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "PATH screen-brightness-mqtt:state-max-loops"
}
