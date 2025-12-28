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

# Convenience: assert a file contains a substring.
# This is intentionally local to this HW test file so it doesn't depend on any
# repo test helper loading conventions.
assert_file_contains() {
  local file="$1"
  local needle="$2"

  [[ -f "$file" ]] || return 1

  local grep_bin="grep"
  if [[ -x /usr/bin/grep ]]; then
    grep_bin="/usr/bin/grep"
  elif [[ -x /bin/grep ]]; then
    grep_bin="/bin/grep"
  fi

  "$grep_bin" -Fq -- "$needle" "$file"
}

wait_for_file() {
  local file="$1"
  local timeout_sec="${2:-5}"
  local end=$((SECONDS + timeout_sec))
  while ((SECONDS < end)); do
    [[ -f "$file" ]] && return 0
    sleep 0.05
  done
  return 1
}

wait_for_file_contains() {
  local file="$1"
  local needle="$2"
  local timeout_sec="${3:-5}"
  local end=$((SECONDS + timeout_sec))

  while ((SECONDS < end)); do
    if assert_file_contains "$file" "$needle"; then
      return 0
    fi
    sleep 0.05
  done

  return 1
}

wait_for_exit() {
  local pid="$1"
  local timeout_sec="${2:-5}"
  local end=$((SECONDS + timeout_sec))
  while kill -0 "$pid" 2>/dev/null; do
    if ((SECONDS >= end)); then
      kill "$pid" 2>/dev/null || true
      sleep 0.1
      kill -9 "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.05
  done
  return 0
}

find_event_for_name() {
  local desired="$1"
  local timeout_sec="${2:-5}"
  local end=$((SECONDS + timeout_sec))

  while ((SECONDS < end)); do
    local name_file
    for name_file in /sys/class/input/event*/device/name; do
      [[ -f "$name_file" ]] || continue
      local n
      n="$(tr -d '\0' <"$name_file" 2>/dev/null || true)"
      # Some kernels/drivers include extra suffix/prefix in the device name.
      if [[ "$n" == *"$desired"* ]]; then
        local event_dir
        # name_file: /sys/class/input/eventX/device/name
        # dirname(dirname(name_file)) => /sys/class/input/eventX
        event_dir="$(basename "$(dirname "$(dirname "$name_file")")")"
        echo "/dev/input/${event_dir}"
        return 0
      fi
    done
    sleep 0.05
  done

  return 1
}

setup() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "Linux-only uinput tests"
  fi

  if ! need_root_or_sudo; then
    skip "Need root or passwordless sudo for /dev/uinput and /dev/input"
  fi

  if [[ ! -e /dev/uinput ]]; then
    if [[ "${KIOSK_RETROPIE_HW_REQUIRE_UINPUT:-0}" == "1" ]]; then
      fail "/dev/uinput missing; load uinput (sudo modprobe uinput)"
    fi
    skip "/dev/uinput not present"
  fi

  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  # Systemctl stub + state.
  SYSTEMCTL_CALLS_FILE="$TEST_DIR/systemctl.calls"
  SYSTEMCTL_STATE_FILE="$TEST_DIR/systemctl.state"
  echo ":kiosk.service:" >"$SYSTEMCTL_STATE_FILE"

  export SYSTEMCTL_CALLS_FILE SYSTEMCTL_STATE_FILE

  STUB_BIN_DIR="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN_DIR"

  cat >"$STUB_BIN_DIR/systemctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

calls_file="${SYSTEMCTL_CALLS_FILE:?}"
state_file="${SYSTEMCTL_STATE_FILE:?}"

# Log commands in a human-readable form so tests can assert via substring match.
printf 'systemctl %s\n' "$*" >>"$calls_file"

cmd="${1:-}"
shift || true

read_state() {
  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo ":"
  fi
}

write_state() {
  local s="$1"
  printf '%s' "$s" >"$state_file"
}

has_unit() {
  local state="$1"
  local unit="$2"
  [[ "$state" == *":${unit}:"* ]]
}

add_unit() {
  local state="$1"
  local unit="$2"
  if has_unit "$state" "$unit"; then
    echo "$state"
  else
    echo "${state}:${unit}:" | sed 's/::/:/g'
  fi
}

rm_unit() {
  local state="$1"
  local unit="$2"
  echo "$state" | sed "s/:${unit}://g"
}

case "$cmd" in
  is-active)
    # Usage: systemctl is-active --quiet UNIT
    if [[ "${1:-}" == "--quiet" ]]; then
      shift
    fi
    unit="${1:-}"
    state="$(read_state)"
    if has_unit "$state" "$unit"; then
      exit 0
    fi
    exit 3
    ;;
  start)
    unit="${1:-}"
    state="$(read_state)"
    state="$(add_unit "$state" "$unit")"
    # Conflicts simulation for kiosk/retro.
    if [[ "$unit" == "retro-mode.service" ]]; then
      state="$(rm_unit "$state" "kiosk.service")"
    fi
    if [[ "$unit" == "kiosk.service" ]]; then
      state="$(rm_unit "$state" "retro-mode.service")"
    fi
    write_state "$state"
    exit 0
    ;;
  stop)
    unit="${1:-}"
    state="$(read_state)"
    state="$(rm_unit "$state" "$unit")"
    write_state "$state"
    exit 0
    ;;
  *)
    # Default: succeed without doing anything.
    exit 0
    ;;
esac
SH

  chmod +x "$STUB_BIN_DIR/systemctl"

  # Uinput emitter.
  FIFO="$TEST_DIR/uinput.fifo"
  mkfifo "$FIFO"
  READY_FILE="$TEST_DIR/uinput.ready"

  export FIFO READY_FILE

  # Run emitter as root (best effort).
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    python3 "$KIOSK_RETROPIE_REPO_ROOT/tests/hw/uinput-emitter.py" "$FIFO" "$READY_FILE" >"$TEST_DIR/uinput.log" 2>&1 &
  else
    sudo -n bash -lc "python3 '$KIOSK_RETROPIE_REPO_ROOT/tests/hw/uinput-emitter.py' '$FIFO' '$READY_FILE' >'$TEST_DIR/uinput.log' 2>&1" &
  fi
  UINPUT_PID=$!

  # Python writes READY_FILE when device is created.
  wait_for_file "$READY_FILE" 8

  # Find the corresponding /dev/input/eventX path.
  EVENT_DEV="$(find_event_for_name "kiosk-retropie-uinput" 20 || true)"
  if [[ -z "$EVENT_DEV" || ! -e "$EVENT_DEV" ]]; then
    if [[ "${KIOSK_RETROPIE_HW_REQUIRE_UINPUT:-0}" == "1" ]]; then
      echo "uinput debug: emitter log" >&2
      sed -n '1,200p' "$TEST_DIR/uinput.log" >&2 || true
      echo "uinput debug: matching sysfs names" >&2
      (ls -1 /sys/class/input/event*/device/name 2>/dev/null | head -n 20 | xargs -I{} sh -c 'printf "%s: %s\n" "{}" "$(tr -d "\\0" <"{}" 2>/dev/null || true)"' | sed -n '1,200p') >&2 || true
      echo "uinput debug: /dev/input snapshot" >&2
      (ls -l /dev/input 2>/dev/null || true) >&2
      fail "Unable to locate /dev/input/event* for uinput device"
    fi
    skip "Unable to locate event device for uinput"
  fi

  export EVENT_DEV
}

teardown() {
  if [[ -n "${UINPUT_PID:-}" ]]; then
    kill "$UINPUT_PID" 2>/dev/null || true
    wait_for_exit "$UINPUT_PID" 2 || true
  fi

  rm -rf "$TEST_DIR" >/dev/null 2>&1 || true
}

emit_combo() {
  local codes=($*)
  printf '%s\n' "${codes[*]}" >"$FIFO"
}

wait_for_listener_listening() {
  local log_file="$1"
  local timeout_sec="${2:-5}"
  wait_for_file_contains "$log_file" "Listening on" "$timeout_sec"
}

@test "TTY listener triggers enter combo via real uinput events" {
  local calls_file="$SYSTEMCTL_CALLS_FILE"

  # Start listener; it will call our stub systemctl.
  PATH="$STUB_BIN_DIR:$PATH" \
    RETROPIE_INPUT_DEVICES="$EVENT_DEV" \
    RETROPIE_ACTION_DEBOUNCE_SEC=0 \
    RETROPIE_MAX_TRIGGERS=1 \
    RETROPIE_MAX_LOOPS=500 \
    bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/input/controller-listener-tty.sh" >"$TEST_DIR/listener.log" 2>&1 &
  local pid=$!

  if ! wait_for_listener_listening "$TEST_DIR/listener.log" 5; then
    echo "DEBUG listener did not start listening" >&2
    sed -n '1,200p' "$TEST_DIR/listener.log" >&2 || true
    fail "Listener did not begin listening"
  fi

  # Default enter is Start (315).
  emit_combo 315

  if ! wait_for_file_contains "$calls_file" "systemctl stop kiosk.service" 8; then
    echo "DEBUG systemctl calls:" >&2
    cat "$calls_file" >&2 || true
    echo "DEBUG listener log:" >&2
    sed -n '1,200p' "$TEST_DIR/listener.log" >&2 || true
    echo "DEBUG uinput emitter log:" >&2
    sed -n '1,200p' "$TEST_DIR/uinput.log" >&2 || true
    fail "Expected systemctl stop kiosk.service"
  fi
  if ! wait_for_file_contains "$calls_file" "systemctl start retro-mode.service" 8; then
    echo "DEBUG systemctl calls:" >&2
    cat "$calls_file" >&2 || true
    echo "DEBUG listener log:" >&2
    sed -n '1,200p' "$TEST_DIR/listener.log" >&2 || true
    echo "DEBUG uinput emitter log:" >&2
    sed -n '1,200p' "$TEST_DIR/uinput.log" >&2 || true
    fail "Expected systemctl start retro-mode.service"
  fi

  wait_for_exit "$pid" 8 || true
}

@test "TTY listener triggers exit combo via real uinput events" {
  # Pretend Retro is already active.
  echo ":retro-mode.service:" >"$SYSTEMCTL_STATE_FILE"

  PATH="$STUB_BIN_DIR:$PATH" \
    RETROPIE_INPUT_DEVICES="$EVENT_DEV" \
    RETROPIE_ACTION_DEBOUNCE_SEC=0 \
    RETROPIE_MAX_TRIGGERS=1 \
    RETROPIE_MAX_LOOPS=800 \
    RETROPIE_EXIT_SEQUENCE_CODES=315,304 \
    RETROPIE_COMBO_WINDOW_SEC=5 \
    bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/input/controller-listener-tty.sh" >"$TEST_DIR/listener-exit.log" 2>&1 &
  local pid=$!

  if ! wait_for_listener_listening "$TEST_DIR/listener-exit.log" 5; then
    echo "DEBUG listener did not start listening" >&2
    sed -n '1,200p' "$TEST_DIR/listener-exit.log" >&2 || true
    fail "Listener did not begin listening"
  fi

  emit_combo 315 304

  if ! wait_for_file_contains "$SYSTEMCTL_CALLS_FILE" "systemctl stop retro-mode.service" 8; then
    echo "DEBUG systemctl calls:" >&2
    cat "$SYSTEMCTL_CALLS_FILE" >&2 || true
    echo "DEBUG listener log:" >&2
    sed -n '1,200p' "$TEST_DIR/listener-exit.log" >&2 || true
    echo "DEBUG uinput emitter log:" >&2
    sed -n '1,200p' "$TEST_DIR/uinput.log" >&2 || true
    fail "Expected systemctl stop retro-mode.service"
  fi
  if ! wait_for_file_contains "$SYSTEMCTL_CALLS_FILE" "systemctl start kiosk.service" 8; then
    echo "DEBUG systemctl calls:" >&2
    cat "$SYSTEMCTL_CALLS_FILE" >&2 || true
    echo "DEBUG listener log:" >&2
    sed -n '1,200p' "$TEST_DIR/listener-exit.log" >&2 || true
    echo "DEBUG uinput emitter log:" >&2
    sed -n '1,200p' "$TEST_DIR/uinput.log" >&2 || true
    fail "Expected systemctl start kiosk.service"
  fi

  wait_for_exit "$pid" 8 || true
}

@test "Kiosk-mode listener starts retro via real uinput events" {
  # Ensure kiosk is active.
  echo ":kiosk.service:" >"$SYSTEMCTL_STATE_FILE"

  # Create a by-id dir pointing at our device.
  local by_id="$TEST_DIR/by-id"
  mkdir -p "$by_id"
  ln -sf "$EVENT_DEV" "$by_id/usb-kiosk-retropie-test-event-joystick"

  # Prefer explicit by-id dir so the script picks the device.
  PATH="$STUB_BIN_DIR:$PATH" \
    RETROPIE_INPUT_BY_ID_DIR="$by_id" \
    RETROPIE_ACTION_DEBOUNCE_SEC=0 \
    RETROPIE_MAX_TRIGGERS=1 \
    RETROPIE_MAX_LOOPS=500 \
    bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/input/controller-listener-kiosk-mode.sh" >"$TEST_DIR/kiosk-listener.log" 2>&1 &
  local pid=$!

  if ! wait_for_listener_listening "$TEST_DIR/kiosk-listener.log" 5; then
    echo "DEBUG listener did not start listening" >&2
    sed -n '1,200p' "$TEST_DIR/kiosk-listener.log" >&2 || true
    fail "Listener did not begin listening"
  fi

  emit_combo 315

  if ! wait_for_file_contains "$SYSTEMCTL_CALLS_FILE" "systemctl start retro-mode.service" 8; then
    echo "DEBUG systemctl calls:" >&2
    cat "$SYSTEMCTL_CALLS_FILE" >&2 || true
    echo "DEBUG listener log:" >&2
    sed -n '1,200p' "$TEST_DIR/kiosk-listener.log" >&2 || true
    echo "DEBUG uinput emitter log:" >&2
    sed -n '1,200p' "$TEST_DIR/uinput.log" >&2 || true
    fail "Expected systemctl start retro-mode.service"
  fi

  wait_for_exit "$pid" 8 || true
}
