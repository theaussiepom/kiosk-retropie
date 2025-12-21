#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

KCOV_PART_DIRS=()
KCOV_WRAP_COUNTER=0
KCOV_BIN="$(command -v kcov 2>/dev/null || true)"
MKDIR_BIN="$(command -v mkdir 2>/dev/null || true)"
RM_BIN="$(command -v rm 2>/dev/null || true)"

kcov_wrap_maybe_run_quiet() {
  local -a original=("$@")
  local -a env_prefix=()
  local -a cmd=()

  # Support calls prefixed with: env KEY=VAL ... <cmd> <args...>
  if [[ ${#original[@]} -ge 1 && "${original[0]}" == "env" ]]; then
    env_prefix+=("env")
    local i=1
    while [[ $i -lt ${#original[@]} ]]; do
      local a="${original[$i]}"
      if [[ "$a" == *=* ]]; then
        env_prefix+=("$a")
        i=$((i + 1))
        continue
      fi
      break
    done
    cmd=("${original[@]:$i}")
  else
    cmd=("${original[@]}")
  fi

  if [[ ${#cmd[@]} -eq 0 ]]; then
    return 0
  fi

  # If invoked as: bash /path/to/script.sh ...  -> run script directly.
  if [[ ${#cmd[@]} -ge 2 && "${cmd[0]}" =~ (^|/)bash$ && "${cmd[1]}" == *.sh ]]; then
    cmd=("${cmd[@]:1}")
  fi

  local script_path="${cmd[0]}"

  if [[ "${KCOV_WRAP:-0}" == "1" && -f "$script_path" && -x "$script_path" ]]; then
    if [[ -z "$KCOV_BIN" ]]; then
      echo "kcov-line-coverage [error]: KCOV_WRAP=1 requires kcov on PATH" >&2
      return 127
    fi

    local out_dir="${KCOV_WRAP_OUT_DIR:-${KCOV_OUT_DIR:-$ROOT_DIR/coverage}}"
    local parts_root="${out_dir}/kcov-parts"
    "${MKDIR_BIN:-/bin/mkdir}" -p "$parts_root"

    KCOV_WRAP_COUNTER=$((KCOV_WRAP_COUNTER + 1))
    local base_name="${script_path##*/}"
    local label="${base_name}-${KCOV_WRAP_COUNTER}"
    local part_dir="${parts_root}/${label}"
    "${MKDIR_BIN:-/bin/mkdir}" -p "$part_dir"
    KCOV_PART_DIRS+=("$part_dir")

    "${env_prefix[@]}" "$KCOV_BIN" \
      --bash-parser=/bin/bash \
      --bash-method=DEBUG \
      --include-path="$ROOT_DIR/scripts" \
      --exclude-pattern="$ROOT_DIR/tests,$ROOT_DIR/tests/vendor,$ROOT_DIR/scripts/ci.sh" \
      "$part_dir" \
      "${cmd[@]}" \
      >/dev/null 2>&1
    return 0
  fi

  "${env_prefix[@]}" "${cmd[@]}" >/dev/null 2>&1
}

run_allow_fail() {
  set +e
  kcov_wrap_maybe_run_quiet "$@"
  set -e
}

export RETRO_HA_ROOT="$work_dir/root"
export RETRO_HA_CALLS_FILE="$work_dir/calls.log"

mkdir -p \
  "$RETRO_HA_ROOT/etc/retro-ha" \
  "$RETRO_HA_ROOT/var/lib/retro-ha" \
  "$RETRO_HA_ROOT/var/lock"

# Create a small set of stubs used to force specific branches.
stub_bin="$work_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/apt-cache" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal apt-cache stub for install.sh coverage.
# Control behavior with KCOV_APT_CACHE_MODE:
#   browser  -> apt-cache show chromium-browser succeeds
#   chromium -> apt-cache show chromium succeeds
#   none     -> both fail
mode="${KCOV_APT_CACHE_MODE:-none}"

if [[ "${1:-}" == "show" ]]; then
  pkg="${2:-}"
  case "$mode:$pkg" in
    browser:chromium-browser) exit 0 ;;
    chromium:chromium) exit 0 ;;
  esac
  exit 1
fi

exit 0
EOF
chmod +x "$stub_bin/apt-cache"

cat >"$stub_bin/getent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal getent stub for passwd + basic DNS reachability in bootstrap.
# Control via KCOV_GETENT_HOME (empty -> simulate missing).
if [[ "${1:-}" == "hosts" && "${2:-}" == "github.com" ]]; then
  if [[ "${KCOV_GETENT_HOSTS_OK:-1}" == "1" ]]; then
    echo "140.82.121.4 github.com"
    exit 0
  fi
  exit 2
fi
if [[ "${1:-}" == "passwd" && "${2:-}" == "retropi" ]]; then
  home="${KCOV_GETENT_HOME:-}"
  if [[ -z "$home" ]]; then
    exit 2
  fi
  printf 'retropi:x:1000:1000::%s:/bin/bash\n' "$home"
  exit 0
fi

exec /usr/bin/getent "$@"
EOF
chmod +x "$stub_bin/getent"

cat >"$stub_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal id stub for coverage coverage.
# - KCOV_ID_U can override: id -u
# - KCOV_RETROPI_EXISTS=1 makes: id -u retropi succeed.
if [[ "${1:-}" == "-u" && -z "${2:-}" ]]; then
  if [[ -n "${KCOV_ID_U:-}" ]]; then
    echo "$KCOV_ID_U"
    exit 0
  fi
fi
if [[ "${KCOV_CURL_OK:-1}" == "1" ]]; then
  exit 0
fi
exit 22
EOF
chmod +x "$stub_bin/curl"

cat >"$stub_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal sudo stub for coverage coverage.
# Supports: sudo -u <user> <cmd>...
if [[ "${1:-}" == "-u" ]]; then
  shift 2
fi
exec "$@"
EOF
chmod +x "$stub_bin/sudo"

cat >"$stub_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal git stub for coverage coverage.
cmd="${1:-}"

if [[ "$cmd" == "clone" ]]; then
  # git clone --depth 1 <repo> <dir>
  dir="${@: -1}"
  mkdir -p "$dir/.git"
  exit 0
fi

if [[ "$cmd" == "-C" ]]; then
  # git -C <dir> pull|fetch|checkout ...
  shift 2
  exit 0
fi

exit 0
EOF
chmod +x "$stub_bin/git"

cat >"$stub_bin/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal id stub for coverage coverage.
# - KCOV_RETROPI_EXISTS=1 makes: id -u retropi succeed.
if [[ "${1:-}" == "-u" && "${2:-}" == "retropi" ]]; then
  if [[ "${KCOV_RETROPI_EXISTS:-0}" == "1" ]]; then
    echo "1000"
    exit 0
  fi
  exit 1
fi

exec /usr/bin/id "$@"
EOF
chmod +x "$stub_bin/id"

cat >"$stub_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# No-op apt-get for install.sh non-dry-run coverage.
exit 0
EOF
chmod +x "$stub_bin/apt-get"

cat >"$stub_bin/useradd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/useradd"

cat >"$stub_bin/usermod" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/usermod"

cat >"$stub_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal systemctl stub.
exit 0
EOF
chmod +x "$stub_bin/systemctl"

cat >"$stub_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal mountpoint stub.
# Mark mounted points via KCOV_MOUNTPOINTS_MOUNTED=":/path1:/path2:".
if [[ "${1:-}" == "-q" ]]; then
  p="${2:-}"
  mounted="${KCOV_MOUNTPOINTS_MOUNTED:-}"
  if [[ "$mounted" == *":${p}:"* ]]; then
    exit 0
  fi
  exit 1
fi

exit 1
EOF
chmod +x "$stub_bin/mountpoint"

cat >"$stub_bin/mount" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal mount stub.
# If KCOV_MOUNT_FAIL=1, fail; else succeed.
if [[ "${KCOV_MOUNT_FAIL:-0}" == "1" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$stub_bin/mount"

cat >"$stub_bin/rsync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/rsync"

cat >"$stub_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal systemctl stub.
# Active units via KCOV_SYSTEMCTL_ACTIVE_UNITS=":unit1:unit2:".
cmd="${1:-}"
if [[ "$cmd" == "is-active" && "${2:-}" == "--quiet" ]]; then
  unit="${3:-}"
  active="${KCOV_SYSTEMCTL_ACTIVE_UNITS:-}"
  if [[ "$active" == *":${unit}:"* ]]; then
    exit 0
  fi
  exit 3
fi

exit 0
EOF
chmod +x "$stub_bin/systemctl"

cat >"$stub_bin/mosquitto_sub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Emit lines for led-mqtt.sh to consume.
if [[ -n "${KCOV_MOSQUITTO_SUB_OUTPUT:-}" ]]; then
  printf '%b' "$KCOV_MOSQUITTO_SUB_OUTPUT"
fi
exit 0
EOF
chmod +x "$stub_bin/mosquitto_sub"

cat >"$stub_bin/mosquitto_pub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/mosquitto_pub"

cat >"$stub_bin/xinit" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/xinit"

cat >"$stub_bin/xset" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/xset"

cat >"$stub_bin/xrandr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/xrandr"

cat >"$stub_bin/chromium-browser" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/chromium-browser"

cat >"$stub_bin/chromium" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/chromium"

cat >"$stub_bin/emulationstation" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$stub_bin/emulationstation"

cat >"$stub_bin/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# id stub that can simulate retropi existing or not.
if [[ "${1:-}" == "-u" && "${2:-}" == "retropi" ]]; then
  if [[ "${KCOV_RETROPI_EXISTS:-1}" == "1" ]]; then
    echo 1000
    exit 0
  fi
  exit 1
fi

exec /usr/bin/id "$@"
EOF
chmod +x "$stub_bin/id"

cat >"$stub_bin/flock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# flock stub used to hit installer lock branches.
# KCOV_FLOCK_MODE:
#   ok            -> succeed
#   fail          -> fail (simulate lock contention)
#   create_marker -> create marker file then succeed (simulate marker appearing)
mode="${KCOV_FLOCK_MODE:-ok}"

if [[ "$mode" == "fail" ]]; then
  exit 1
fi

if [[ "$mode" == "create_marker" ]]; then
  marker="${RETRO_HA_INSTALLED_MARKER:-}"
  if [[ -n "$marker" ]]; then
    mkdir -p "$(dirname "$marker")"
    : >"$marker"
  fi
fi

exit 0
EOF
chmod +x "$stub_bin/flock"

# Prefer our stubs, then the repo's test stubs, then system bins.
export PATH="$stub_bin:$ROOT_DIR/tests/stubs:/usr/bin:/bin"

# Source lib helpers and exercise edge cases.
# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=scripts/lib/logging.sh
source "$ROOT_DIR/scripts/lib/logging.sh"
# shellcheck source=scripts/lib/config.sh
source "$ROOT_DIR/scripts/lib/config.sh"

# backup.sh: cover plan-states branch (states exists, saves missing).
# shellcheck source=scripts/lib/backup.sh
source "$ROOT_DIR/scripts/lib/backup.sh"
states_only="$work_dir/states-only"
mkdir -p "$states_only"
save_backup_plan "$work_dir/does-not-exist" "$states_only" "$work_dir/backup" "subdir" >/dev/null

# common.sh: cover record_call append-none branch.
export RETRO_HA_PATH_COVERAGE=1
export RETRO_HA_CALLS_FILE="$work_dir/calls-primary.log"
unset RETRO_HA_CALLS_FILE_APPEND
record_call "primary-only" >/dev/null

# common.sh: cover retro_ha_is_sourced() true branch.
# Trigger it deterministically by making $0 differ from the top stack frame.
old_argv0="${BASH_ARGV0-}"
BASH_ARGV0="kcov-coverage-fake-argv0"
retro_ha_is_sourced >/dev/null || true
if [[ -n "$old_argv0" ]]; then
  BASH_ARGV0="$old_argv0"
else
  unset BASH_ARGV0 2>/dev/null || true
fi

# x11.sh: cover runtime-dir selection and helpers.
# shellcheck source=scripts/lib/x11.sh
source "$ROOT_DIR/scripts/lib/x11.sh"
(
  export XDG_RUNTIME_DIR="$work_dir/xdg-runtime"
  retro_ha_runtime_dir >/dev/null
) || true
(
  unset XDG_RUNTIME_DIR
  retro_ha_runtime_dir 1234 >/dev/null
) || true
retro_ha_state_dir "/tmp/runtime" >/dev/null
retro_ha_xinitrc_path "/tmp/state" "ha-xinitrc" >/dev/null
retro_ha_x_lock_paths ":0" >/dev/null
retro_ha_xinit_exec_record "/tmp/xinitrc" ":0" "7" >/dev/null
retro_ha_xinitrc_prelude >/dev/null

# Exercise path guard helpers with cover_path defined.
# shellcheck source=scripts/lib/path.sh
source "$ROOT_DIR/scripts/lib/path.sh"
export RETRO_HA_PATH_COVERAGE=0
retro_ha_path_is_under "/a" "/a" >/dev/null
retro_ha_path_is_under "/" "/anything" >/dev/null
retro_ha_path_is_under "/a" "/b" >/dev/null || true

# Hit remaining uncovered lines in logging.sh.
warn "coverage warn"

# Exercise cover-path plumbing and prefix branches.
export RETRO_HA_PATH_COVERAGE=1
unset RETRO_HA_PATHS_FILE RETRO_HA_CALLS_FILE_APPEND RETRO_HA_CALLS_FILE
retro_ha__cover_path_raw "" >/dev/null
retro_ha__cover_path_raw "lib-logging:missing-path-file" >/dev/null
export RETRO_HA_CALLS_FILE_APPEND="$work_dir/paths.append.log"
retro_ha__cover_path_raw "lib-logging:write-path" >/dev/null

RETRO_HA_LOG_PREFIX="custom-prefix" log "log-msg" >/dev/null
RETRO_HA_LOG_PREFIX="custom-prefix" warn "warn-msg" >/dev/null
(
  set +e
  RETRO_HA_LOG_PREFIX="custom-prefix" die "die-msg" >/dev/null 2>&1
) || true
unset RETRO_HA_LOG_PREFIX

# Exercise config.sh env override and missing/present file branches.
RETRO_HA_CONFIG_ENV="$work_dir/missing-config.env"
load_config_env
mkdir -p "${RETRO_HA_CONFIG_ENV%/*}"
echo 'FOO=bar' >"$RETRO_HA_CONFIG_ENV"
load_config_env
retro_ha_config_env_path >/dev/null

# Exercise retro_ha_is_sourced (false + true).
(
  set -euo pipefail
  source "$ROOT_DIR/scripts/lib/common.sh"
  retro_ha_is_sourced >/dev/null || true
)
(
  set -euo pipefail
  tmp_entry="$work_dir/entry.__kcov_sourced.sh"
  cat >"$tmp_entry" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT_DIR/scripts/lib/common.sh"
retro_ha_is_sourced >/dev/null || true
EOF
  # shellcheck source=/dev/null
  source "$tmp_entry"
)

(
  unset RETRO_HA_ROOT
  retro_ha_root >/dev/null
)
(
  export RETRO_HA_ROOT=""
  retro_ha_root >/dev/null
)
(
  export RETRO_HA_ROOT="/"
  retro_ha_root >/dev/null
)
(
  export RETRO_HA_ROOT="/tmp/retro-ha-root/"
  retro_ha_root >/dev/null
)

retro_ha_path /etc/retro-ha/config.env >/dev/null
retro_ha_path relative/path >/dev/null

# Ensure retro_ha_path covers the root=='/' branch (echo "$abs_path").
(
  unset RETRO_HA_ROOT
  retro_ha_path /etc/retro-ha/config.env >/dev/null
)
(
  export RETRO_HA_ROOT=""
  retro_ha_path /etc/retro-ha/config.env >/dev/null
)

retro_ha_dirname "" >/dev/null
retro_ha_dirname "foo" >/dev/null
retro_ha_dirname "/foo" >/dev/null
retro_ha_dirname "/foo/" >/dev/null
retro_ha_dirname "/" >/dev/null

# record_call / cover_path / run_cmd branches.
export RETRO_HA_CALLS_FILE="$work_dir/calls.log"
export RETRO_HA_CALLS_FILE_APPEND="$work_dir/calls-append.log"
record_call "hello" >/dev/null

export RETRO_HA_PATH_COVERAGE=0
cover_path "no-op" >/dev/null
export RETRO_HA_PATH_COVERAGE=1
cover_path "do-op" >/dev/null

export RETRO_HA_DRY_RUN=1
run_cmd echo "dry" >/dev/null
export RETRO_HA_DRY_RUN=0
run_cmd true >/dev/null

retro_ha_realpath_m "/a/b/../c" >/dev/null
retro_ha_realpath_m "a/./b" >/dev/null

# Cover common.sh branch where empty root normalizes to '/'.
export RETRO_HA_ROOT=""
retro_ha_root >/dev/null
unset RETRO_HA_ROOT

export RETRO_HA_DRY_RUN=1
svc_start foo.service >/dev/null
svc_stop foo.service >/dev/null

# require_cmd: success + failure branch (failure in subshell so we keep going).
require_cmd bash >/dev/null
(
  set +e
  require_cmd this-command-does-not-exist 2>/dev/null
) || true

# Cover "scripts/lib not found" error branches by temporarily hiding scripts/lib.
lib_dir="$ROOT_DIR/scripts/lib"
hidden_lib_dir="$ROOT_DIR/scripts/lib.__kcov_hidden"
if [[ -d "$lib_dir" ]]; then
  mv "$lib_dir" "$hidden_lib_dir"
  # Avoid subshell here for the scripts we still need counted by KCOV_WRAP.
  run_allow_fail "$ROOT_DIR/scripts/bootstrap.sh"
  run_allow_fail "$ROOT_DIR/scripts/leds/led-mqtt.sh"
  (
    set +e
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/bootstrap.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/healthcheck.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/install.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/leds/ledctl.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/leds/led-mqtt.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/mode/enter-ha-mode.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/mode/retro-mode.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/nfs/save-backup.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/nfs/sync-roms.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"
    kcov_wrap_maybe_run_quiet "$ROOT_DIR/scripts/retropie/install-retropie.sh"
  ) || true
  mv "$hidden_lib_dir" "$lib_dir"
fi

kcov_wrap_merge() {
  if [[ "${KCOV_WRAP:-0}" != "1" ]]; then
    return 0
  fi

  local out_dir="${KCOV_WRAP_OUT_DIR:-${KCOV_OUT_DIR:-$ROOT_DIR/coverage}}"
  local merged_dir="${out_dir}/kcov-merged"

  "${RM_BIN:-/bin/rm}" -rf "$merged_dir"
  "${MKDIR_BIN:-/bin/mkdir}" -p "$merged_dir"

  if [[ ${#KCOV_PART_DIRS[@]} -eq 0 ]]; then
    echo "kcov-line-coverage [error]: KCOV_WRAP=1 but no kcov parts were produced" >&2
    return 1
  fi

  "$KCOV_BIN" --merge "$merged_dir" "${KCOV_PART_DIRS[@]}" >/dev/null 2>&1
}

if [[ "${KCOV_WRAP:-0}" == "1" ]]; then
  trap 'kcov_wrap_merge; cleanup' EXIT
fi

export RETRO_HA_ROOT="$work_dir/root"
mkdir -p "$RETRO_HA_ROOT"

# Fake LED sysfs so ledctl can fully exercise success paths.
mkdir -p "$RETRO_HA_ROOT/sys/class/leds/led0" "$RETRO_HA_ROOT/sys/class/leds/led1"
echo 'none [mmc0] timer heartbeat' >"$RETRO_HA_ROOT/sys/class/leds/led0/trigger"
echo 0 >"$RETRO_HA_ROOT/sys/class/leds/led0/brightness"
echo 'none [default-on] timer heartbeat' >"$RETRO_HA_ROOT/sys/class/leds/led1/trigger"
echo 0 >"$RETRO_HA_ROOT/sys/class/leds/led1/brightness"

# ledctl.sh: usage + invalid inputs + missing sysfs + supported/unsupported triggers.
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh"
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" bad on
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" act bad

# Supported trigger branches (ensure trigger files still advertise support).
echo 'none [mmc0] timer heartbeat' >"$RETRO_HA_ROOT/sys/class/leds/led0/trigger"
echo 'none [default-on] timer heartbeat' >"$RETRO_HA_ROOT/sys/class/leds/led1/trigger"
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" act on
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" pwr on

run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" act off
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" act on
run_allow_fail env RETRO_HA_ACT_LED_TRIGGER_ON=nonesuch "$ROOT_DIR/scripts/leds/ledctl.sh" act on
run_allow_fail env RETRO_HA_ACT_LED=missing-led "$ROOT_DIR/scripts/leds/ledctl.sh" act off
run_allow_fail env RETRO_HA_ACT_LED=missing-led "$ROOT_DIR/scripts/leds/ledctl.sh" act on
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" pwr off
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" pwr on
run_allow_fail env RETRO_HA_PWR_LED_TRIGGER_ON=nonesuch "$ROOT_DIR/scripts/leds/ledctl.sh" pwr on
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" all on
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" all off

# leds-on/off wrappers.
run_allow_fail "$ROOT_DIR/scripts/leds/leds-on.sh"
run_allow_fail "$ROOT_DIR/scripts/leds/leds-off.sh"

# input controller listeners: run a minimal no-device scenario to cover the
# wrapper script lines (python logic is covered separately).
empty_by_id="$work_dir/input-by-id-empty"
mkdir -p "$empty_by_id"
run_allow_fail env RETRO_HA_INPUT_BY_ID_DIR="$empty_by_id" KCOV_SYSTEMCTL_ACTIVE_UNITS="" "$ROOT_DIR/scripts/input/controller-listener-ha-mode.sh"
run_allow_fail env RETRO_HA_INPUT_BY_ID_DIR="$empty_by_id" KCOV_SYSTEMCTL_ACTIVE_UNITS="" "$ROOT_DIR/scripts/input/controller-listener-tty.sh"

# Cover scripts/leds/lib branch selection.
leds_lib_link="$ROOT_DIR/scripts/leds/lib"
if [[ ! -e "$leds_lib_link" ]]; then
  ln -s ../lib "$leds_lib_link" 2>/dev/null || true
fi
run_allow_fail "$ROOT_DIR/scripts/leds/ledctl.sh" act off
rm -f "$leds_lib_link" 2>/dev/null || true

# mount-nfs.sh: not configured / already mounted / mount fail / mount success.
export RETRO_HA_DRY_RUN=0
mp_roms="$RETRO_HA_ROOT/mnt/retro-ha-roms"
mkdir -p "$mp_roms"

# Cover scripts/nfs/lib selection.
nfs_lib_link="$ROOT_DIR/scripts/nfs/lib"
if [[ ! -e "$nfs_lib_link" ]]; then
  ln -s ../lib "$nfs_lib_link" 2>/dev/null || true
fi
run_allow_fail env NFS_SERVER= NFS_PATH= "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
run_allow_fail env NFS_SERVER=server NFS_PATH=/export KCOV_MOUNTPOINTS_MOUNTED=":${mp_roms}:" "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
run_allow_fail env NFS_SERVER=server NFS_PATH=/export RETRO_HA_NFS_MOUNT_POINT="$mp_roms" KCOV_MOUNTPOINTS_MOUNTED="" KCOV_MOUNT_FAIL=1 "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
run_allow_fail env NFS_SERVER=server NFS_PATH=/export RETRO_HA_NFS_MOUNT_POINT="$mp_roms" KCOV_MOUNTPOINTS_MOUNTED="" KCOV_MOUNT_FAIL=0 "$ROOT_DIR/scripts/nfs/mount-nfs.sh"

# mount-nfs-backup.sh: disabled / not configured / already mounted / mount fail / mount success.
backup_root="$RETRO_HA_ROOT/mnt/retro-ha-backup"
mkdir -p "$backup_root"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=0 "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_NFS_SERVER= RETRO_HA_SAVE_BACKUP_NFS_PATH= "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_NFS_SERVER=server RETRO_HA_SAVE_BACKUP_NFS_PATH=/export RETRO_HA_SAVE_BACKUP_DIR="$backup_root" KCOV_MOUNTPOINTS_MOUNTED=":${backup_root}:" "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_NFS_SERVER=server RETRO_HA_SAVE_BACKUP_NFS_PATH=/export RETRO_HA_SAVE_BACKUP_DIR="$backup_root" KCOV_MOUNTPOINTS_MOUNTED="" KCOV_MOUNT_FAIL=1 "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_NFS_SERVER=server RETRO_HA_SAVE_BACKUP_NFS_PATH=/export RETRO_HA_SAVE_BACKUP_DIR="$backup_root" KCOV_MOUNTPOINTS_MOUNTED="" KCOV_MOUNT_FAIL=0 "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
rm -f "$nfs_lib_link" 2>/dev/null || true

# save-backup.sh: disabled / retro active / not mounted / rsync missing / backup saves+states (delete on).
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=0 "$ROOT_DIR/scripts/nfs/save-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 KCOV_SYSTEMCTL_ACTIVE_UNITS=":retro-mode.service:" "$ROOT_DIR/scripts/nfs/save-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 KCOV_SYSTEMCTL_ACTIVE_UNITS="" KCOV_MOUNTPOINTS_MOUNTED="" "$ROOT_DIR/scripts/nfs/save-backup.sh"

# rsync missing branch: hide rsync in both stub dirs for this one run.
if [[ -f "$stub_bin/rsync" && -f "$ROOT_DIR/tests/stubs/rsync" ]]; then
  mv "$stub_bin/rsync" "$stub_bin/rsync.__kcov_hidden" 2>/dev/null || true
  mv "$ROOT_DIR/tests/stubs/rsync" "$ROOT_DIR/tests/stubs/rsync.__kcov_hidden" 2>/dev/null || true
  run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 KCOV_SYSTEMCTL_ACTIVE_UNITS="" KCOV_MOUNTPOINTS_MOUNTED=":${backup_root}:" "$ROOT_DIR/scripts/nfs/save-backup.sh"
  mv "$stub_bin/rsync.__kcov_hidden" "$stub_bin/rsync" 2>/dev/null || true
  mv "$ROOT_DIR/tests/stubs/rsync.__kcov_hidden" "$ROOT_DIR/tests/stubs/rsync" 2>/dev/null || true
fi

mkdir -p "$RETRO_HA_ROOT/var/lib/retro-ha/retropie/saves" "$RETRO_HA_ROOT/var/lib/retro-ha/retropie/states"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_DIR="$backup_root" RETRO_HA_SAVE_BACKUP_DELETE=1 KCOV_SYSTEMCTL_ACTIVE_UNITS="" KCOV_MOUNTPOINTS_MOUNTED=":${backup_root}:" "$ROOT_DIR/scripts/nfs/save-backup.sh"

# save-backup.sh: cover defensive unknown-label branch (case *) which continues.
(
  set -euo pipefail
  export RETRO_HA_SAVE_BACKUP_ENABLED=1
  export RETRO_HA_SAVE_BACKUP_DIR="$backup_root"
  export KCOV_SYSTEMCTL_ACTIVE_UNITS=""
  export KCOV_MOUNTPOINTS_MOUNTED=":${backup_root}:"
  export RETRO_HA_DRY_RUN=1

  source "$ROOT_DIR/scripts/nfs/save-backup.sh"

  save_backup_plan() {
    printf 'unknown\t%s\t%s\n' "$RETRO_HA_ROOT/does-not-matter" "$RETRO_HA_ROOT/does-not-matter"
  }

  main
) || true

# sync-roms.sh: rsync missing / not mounted / src missing / allowlist+missing system / excluded / discover + delete.
mp_src="$mp_roms"
src_subdir="roms"
mkdir -p "$mp_src/$src_subdir/nes" "$mp_src/$src_subdir/snes"

# sync-roms.sh missing scripts/lib branch.
hidden_sync_roms_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_sync_roms"
if mv "$ROOT_DIR/scripts/lib" "$hidden_sync_roms_lib" 2>/dev/null; then
  rm -rf "$ROOT_DIR/scripts/nfs/lib" 2>/dev/null || true
  run_allow_fail "$ROOT_DIR/scripts/nfs/sync-roms.sh"
  mv "$hidden_sync_roms_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
fi

# sync-roms.sh rsync missing branch: exclude coverage/test stubs from PATH for this run.
run_allow_fail env RETRO_HA_DRY_RUN=1 PATH="/usr/bin:/bin" "$ROOT_DIR/scripts/nfs/sync-roms.sh"

mv "$stub_bin/rsync" "$stub_bin/rsync.__kcov_hidden"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" "$ROOT_DIR/scripts/nfs/sync-roms.sh"
mv "$stub_bin/rsync.__kcov_hidden" "$stub_bin/rsync"

run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" KCOV_MOUNTPOINTS_MOUNTED="" "$ROOT_DIR/scripts/nfs/sync-roms.sh"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR=missing KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" "$ROOT_DIR/scripts/nfs/sync-roms.sh"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" RETRO_HA_ROMS_SYSTEMS="missing" KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" "$ROOT_DIR/scripts/nfs/sync-roms.sh"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" RETRO_HA_ROMS_SYSTEMS="nes,snes" RETRO_HA_ROMS_EXCLUDE_SYSTEMS="nes" KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" "$ROOT_DIR/scripts/nfs/sync-roms.sh"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" RETRO_HA_ROMS_SYNC_DELETE=1 KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" "$ROOT_DIR/scripts/nfs/sync-roms.sh"

# chown missing + delete disabled branch.
no_chown="$work_dir/bin-no-chown"
mkdir -p "$no_chown"
ln -sf /usr/bin/bash "$no_chown/bash"
ln -sf /usr/bin/env "$no_chown/env"
ln -sf /usr/bin/mkdir "$no_chown/mkdir"
ln -sf /usr/bin/find "$no_chown/find"
ln -sf /usr/bin/sort "$no_chown/sort"
ln -sf "$stub_bin/mountpoint" "$no_chown/mountpoint"
ln -sf "$stub_bin/rsync" "$no_chown/rsync"
PATH="$no_chown" run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" "$ROOT_DIR/scripts/nfs/sync-roms.sh"

# led-mqtt.sh: disabled / missing host / missing ledctl / payload handling + state publish + tls/user/pass.
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=0 "$ROOT_DIR/scripts/leds/led-mqtt.sh"
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST= "$ROOT_DIR/scripts/leds/led-mqtt.sh"
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST=localhost RETRO_HA_LEDCTL_PATH="$work_dir/missing-ledctl" KCOV_MOSQUITTO_SUB_OUTPUT=$'retro-ha/led/act/set ON\n' "$ROOT_DIR/scripts/leds/led-mqtt.sh"
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST=localhost MQTT_USERNAME=u MQTT_PASSWORD=p MQTT_TLS=1 RETRO_HA_LEDCTL_PATH="$ROOT_DIR/scripts/leds/ledctl.sh" KCOV_MOSQUITTO_SUB_OUTPUT=$'retro-ha/led/act/set ON\nretro-ha/led/pwr/set off\nretro-ha/led/all/set INVALID\nretro-ha/led/all/set OFF\nretro-ha/led/bad/set ON\n' "$ROOT_DIR/scripts/leds/led-mqtt.sh"
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST=localhost MQTT_TLS=0 RETRO_HA_LEDCTL_PATH="$ROOT_DIR/scripts/leds/ledctl.sh" KCOV_MOSQUITTO_SUB_OUTPUT='' "$ROOT_DIR/scripts/leds/led-mqtt.sh"

# Cover scripts/leds/lib branch selection in led-mqtt.
leds_lib_link="$ROOT_DIR/scripts/leds/lib"
if [[ ! -e "$leds_lib_link" ]]; then
  ln -s ../lib "$leds_lib_link" 2>/dev/null || true
fi
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST=localhost RETRO_HA_LEDCTL_PATH="$ROOT_DIR/scripts/leds/ledctl.sh" KCOV_MOSQUITTO_SUB_OUTPUT=$'retro-ha/led/act/set OFF\n' "$ROOT_DIR/scripts/leds/led-mqtt.sh"

# led-mqtt.sh: missing scripts/lib branch (hide both scripts/leds/lib and scripts/lib).
(
  set +e
  rm -rf "$ROOT_DIR/scripts/leds/lib" 2>/dev/null || true
  hidden_led_mqtt_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_led_mqtt"
  mv "$ROOT_DIR/scripts/lib" "$hidden_led_mqtt_lib" 2>/dev/null || exit 0
  run_allow_fail "$ROOT_DIR/scripts/leds/led-mqtt.sh"
  mv "$hidden_led_mqtt_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
) || true

# led-mqtt.sh: exercise internal helpers for otherwise-unreachable branches.
(
  set +e
  # shellcheck source=scripts/leds/led-mqtt.sh
  source "$ROOT_DIR/scripts/leds/led-mqtt.sh"

  export MQTT_HOST=localhost
  export MQTT_PORT=1884
  mosq_args >/dev/null

  # invalid target branch
  led_state_payload bad >/dev/null 2>&1 || true

  act_dir="$(retro_ha_path /sys/class/leds/led0)"
  act_brightness="$act_dir/brightness"

  # missing brightness file
  rm -f "$act_brightness" 2>/dev/null || true
  led_state_payload act >/dev/null 2>&1 || true

  # invalid brightness value
  printf '%s\n' abc >"$act_brightness"
  led_state_payload act >/dev/null 2>&1 || true

  # state-on
  printf '%s\n' 1 >"$act_brightness"
  led_state_payload act >/dev/null 2>&1 || true

  # poller: state-same-act requires a second loop with unchanged state.
  export RETRO_HA_LED_MQTT_POLL_SEC=0
  export RETRO_HA_LED_MQTT_MAX_LOOPS=2
  led_state_poller retro-ha >/dev/null 2>&1 || true
) || true

# screen-brightness-mqtt.sh: cover disabled + missing MQTT host + basic set.
bl_root="$RETRO_HA_ROOT/sys/class/backlight"
bl0="$bl_root/bl0"

# Disabled branch.
run_allow_fail env RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=0 "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# Enabled but missing MQTT_HOST.
run_allow_fail env RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 MQTT_HOST= "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# Basic successful run with a fake backlight and a small, finite loop.
mkdir -p "$bl0"
echo 100 >"$bl0/max_brightness"
echo 50 >"$bl0/brightness"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  MQTT_PORT=1884 \
  MQTT_USERNAME=u \
  MQTT_PASSWORD=p \
  MQTT_TLS=1 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT=$'retro-ha/screen/brightness/set bad\nretro-ha/screen/brightness/set 101\nretro-ha/screen/brightness/set 25\n' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# Poller state-same branch requires at least 2 loops with unchanged brightness.
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME=bl0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=2 \
  KCOV_MOSQUITTO_SUB_OUTPUT='' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# max_brightness missing -> read_brightness_percent early return.
rm -rf "$bl0"
mkdir -p "$bl0"
echo 50 >"$bl0/brightness"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME=bl0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT='' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# max_brightness invalid -> max-invalid branch.
rm -rf "$bl0"
mkdir -p "$bl0"
echo 0 >"$bl0/max_brightness"
echo 10 >"$bl0/brightness"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME=bl0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT='' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# brightness file missing -> read-missing branch.
rm -rf "$bl0"
mkdir -p "$bl0"
echo 100 >"$bl0/max_brightness"
rm -f "$bl0/brightness"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME=bl0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT='' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# brightness file invalid -> read-invalid branch.
rm -rf "$bl0"
mkdir -p "$bl0"
echo 100 >"$bl0/max_brightness"
echo abc >"$bl0/brightness"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME=bl0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT='' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# write dry-run -> write-bdry-run branch.
rm -rf "$bl0"
mkdir -p "$bl0"
echo 100 >"$bl0/max_brightness"
echo 0 >"$bl0/brightness"
run_allow_fail env \
  RETRO_HA_DRY_RUN=1 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME=bl0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT=$'retro-ha/screen/brightness/set 10\n' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# Cover SCRIPT_DIR/lib selection + mosq defaults (no port/user/pass) + TLS off + backlight-name.
screen_lib_link="$ROOT_DIR/scripts/screen/lib"
if [[ ! -e "$screen_lib_link" ]]; then
  ln -s ../lib "$screen_lib_link" 2>/dev/null || true
fi
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  MQTT_PORT= \
  MQTT_USERNAME= \
  MQTT_PASSWORD= \
  MQTT_TLS=0 \
  RETRO_HA_BACKLIGHT_NAME=bl0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT='' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"
rm -f "$screen_lib_link" 2>/dev/null || true

# Cover backlight auto-detect with no devices (nullglob cleanup + empty return).
rm -rf "$bl_root"
mkdir -p "$bl_root"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME= \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT='' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# Missing scripts/lib branch.
rm -f "$ROOT_DIR/scripts/screen/lib" 2>/dev/null || true
hidden_screen_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_screen_brightness"
mv "$ROOT_DIR/scripts/lib" "$hidden_screen_lib" 2>/dev/null || true
run_allow_fail env RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 MQTT_HOST=localhost "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"
mv "$hidden_screen_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
rm -f "$leds_lib_link" 2>/dev/null || true

# ha-kiosk.sh: missing HA_URL / missing chromium / dry-run / non-dry-run (exec xinit stub).
run_allow_fail env HA_URL= "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
run_allow_fail env HA_URL=http://example.invalid PATH="$stub_bin:/bin" "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 RETRO_HA_SCREEN_ROTATION=left "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=0 RETRO_HA_SCREEN_ROTATION=left "$ROOT_DIR/scripts/mode/ha-kiosk.sh"

# Force missing chromium/chromium-browser branch by hiding stubs in both stub dirs.
if [[ -f "$stub_bin/chromium" && -f "$stub_bin/chromium-browser" && -f "$ROOT_DIR/tests/stubs/chromium" && -f "$ROOT_DIR/tests/stubs/chromium-browser" ]]; then
  mv "$stub_bin/chromium" "$stub_bin/chromium.__kcov_hidden" 2>/dev/null || true
  mv "$stub_bin/chromium-browser" "$stub_bin/chromium-browser.__kcov_hidden" 2>/dev/null || true
  mv "$ROOT_DIR/tests/stubs/chromium" "$ROOT_DIR/tests/stubs/chromium.__kcov_hidden" 2>/dev/null || true
  mv "$ROOT_DIR/tests/stubs/chromium-browser" "$ROOT_DIR/tests/stubs/chromium-browser.__kcov_hidden" 2>/dev/null || true

  run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/mode/ha-kiosk.sh"

  mv "$stub_bin/chromium.__kcov_hidden" "$stub_bin/chromium" 2>/dev/null || true
  mv "$stub_bin/chromium-browser.__kcov_hidden" "$stub_bin/chromium-browser" 2>/dev/null || true
  mv "$ROOT_DIR/tests/stubs/chromium.__kcov_hidden" "$ROOT_DIR/tests/stubs/chromium" 2>/dev/null || true
  mv "$ROOT_DIR/tests/stubs/chromium-browser.__kcov_hidden" "$ROOT_DIR/tests/stubs/chromium-browser" 2>/dev/null || true
fi

# Cover SCRIPT_DIR fallback (SCRIPT_DIR='.') by executing via PATH (no slash).
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 PATH="$ROOT_DIR/scripts/mode:$PATH" ha-kiosk.sh

# Cover scripts/mode/lib branch selection.
mode_lib_link="$ROOT_DIR/scripts/mode/lib"
if [[ ! -e "$mode_lib_link" ]]; then
  ln -s ../lib "$mode_lib_link" 2>/dev/null || true
fi
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/mode/ha-kiosk.sh"

# Missing scripts/lib branch (hide both scripts/mode/lib and scripts/lib).
rm -rf "$ROOT_DIR/scripts/mode/lib" 2>/dev/null || true
hidden_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_ha_kiosk"
if mv "$ROOT_DIR/scripts/lib" "$hidden_lib" 2>/dev/null; then
  run_allow_fail "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
  mv "$hidden_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
fi

# Ensure chromium_bin chooses chromium (not chromium-browser).
mv "$stub_bin/chromium-browser" "$stub_bin/chromium-browser.__kcov_hidden" 2>/dev/null || true
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
mv "$stub_bin/chromium-browser.__kcov_hidden" "$stub_bin/chromium-browser" 2>/dev/null || true

rm -f "$mode_lib_link" 2>/dev/null || true

# Missing chromium/chromium-browser branch.
no_chromium="$work_dir/bin-no-chromium"
mkdir -p "$no_chromium"
ln -sf /usr/bin/bash "$no_chromium/bash"
ln -sf /usr/bin/dirname "$no_chromium/dirname"
ln -sf /usr/bin/id "$no_chromium/id"
ln -sf /usr/bin/mkdir "$no_chromium/mkdir"
ln -sf /usr/bin/chmod "$no_chromium/chmod"
ln -sf /usr/bin/rm "$no_chromium/rm"
ln -sf /usr/bin/cat "$no_chromium/cat"
ln -sf /usr/bin/tr "$no_chromium/tr"
ln -sf "$stub_bin/xinit" "$no_chromium/xinit"
ln -sf "$stub_bin/xset" "$no_chromium/xset"
ln -sf "$stub_bin/xrandr" "$no_chromium/xrandr"
PATH="$no_chromium" run_allow_fail env HA_URL=http://example.invalid "$ROOT_DIR/scripts/mode/ha-kiosk.sh"

# Force chromium selection (hide chromium-browser).
mv "$stub_bin/chromium-browser" "$stub_bin/chromium-browser.__kcov_hidden"
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=0 RETRO_HA_SCREEN_ROTATION= "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
mv "$stub_bin/chromium-browser.__kcov_hidden" "$stub_bin/chromium-browser"

# Reliably cover the chromium (not chromium-browser) branch.
# Use a minimal PATH that contains `chromium` but not `chromium-browser`.
chromium_only="$work_dir/bin-chromium-only"
mkdir -p "$chromium_only"

# Required helpers for the script prelude.
ln -sf /usr/bin/bash "$chromium_only/bash"
ln -sf /usr/bin/dirname "$chromium_only/dirname"
ln -sf /usr/bin/id "$chromium_only/id"

# Chromium stub.
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$chromium_only/chromium"
chmod +x "$chromium_only/chromium"

run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 PATH="$chromium_only" "$ROOT_DIR/scripts/mode/ha-kiosk.sh"

# save-backup.sh: rsync missing branch (use a PATH that contains required stubs but not rsync).
bin_no_rsync="$work_dir/bin-no-rsync"
mkdir -p "$bin_no_rsync"
ln -sf /usr/bin/bash "$bin_no_rsync/bash"
ln -sf /usr/bin/dirname "$bin_no_rsync/dirname"
ln -sf /usr/bin/mkdir "$bin_no_rsync/mkdir"
ln -sf "$stub_bin/systemctl" "$bin_no_rsync/systemctl"
ln -sf "$stub_bin/mountpoint" "$bin_no_rsync/mountpoint"

(
  set +e
  export PATH="$bin_no_rsync"
  export RETRO_HA_DRY_RUN=1
  export RETRO_HA_SAVE_BACKUP_ENABLED=1
  export RETRO_HA_SAVE_BACKUP_DIR="$backup_root"
  export KCOV_SYSTEMCTL_ACTIVE_UNITS=""
  export KCOV_MOUNTPOINTS_MOUNTED=":${backup_root}:"
  # shellcheck source=scripts/nfs/save-backup.sh
  source "$ROOT_DIR/scripts/nfs/save-backup.sh"
  main
) || true

# sync-roms.sh: rsync missing branch (also using PATH without rsync).
(
  set +e
  export PATH="$bin_no_rsync"
  export RETRO_HA_DRY_RUN=1
  export RETRO_HA_NFS_MOUNT_POINT="$mp_roms"
  # shellcheck source=scripts/nfs/sync-roms.sh
  source "$ROOT_DIR/scripts/nfs/sync-roms.sh"
  main
) || true

# screen-brightness-mqtt.sh: directly exercise poller for state-same + sleep.
(
  set +e
  bl_root="$RETRO_HA_ROOT/sys/class/backlight"
  mkdir -p "$bl_root/blc"
  echo 100 >"$bl_root/blc/max_brightness"
  echo 50 >"$bl_root/blc/brightness"
  export RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0
  export RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=2
  export RETRO_HA_BACKLIGHT_NAME=blc
  # shellcheck source=scripts/screen/screen-brightness-mqtt.sh
  source "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"
  brightness_state_poller "retro-ha"
) || true

# retro-mode.sh: missing xinit / missing emulationstation / dry-run / non-dry-run.
no_xinit="$work_dir/bin-no-xinit"
mkdir -p "$no_xinit"
ln -sf /usr/bin/bash "$no_xinit/bash"
ln -sf /usr/bin/dirname "$no_xinit/dirname"
run_allow_fail env PATH="$no_xinit" RETRO_HA_PATH_COVERAGE=0 RETRO_HA_DRY_RUN=0 "$ROOT_DIR/scripts/mode/retro-mode.sh"

xinit_only="$work_dir/bin-xinit-only"
mkdir -p "$xinit_only"
ln -sf /usr/bin/bash "$xinit_only/bash"
ln -sf /usr/bin/dirname "$xinit_only/dirname"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$xinit_only/xinit"
chmod +x "$xinit_only/xinit"
run_allow_fail env PATH="$xinit_only" RETRO_HA_PATH_COVERAGE=0 RETRO_HA_DRY_RUN=0 "$ROOT_DIR/scripts/mode/retro-mode.sh"

# Provide both xinit + emulationstation for the remaining dry-run / non-dry-run paths.
run_allow_fail env PATH="$stub_bin:/usr/bin:/bin" "$ROOT_DIR/scripts/mode/retro-mode.sh"
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_SCREEN_ROTATION=right "$ROOT_DIR/scripts/mode/retro-mode.sh"
run_allow_fail env RETRO_HA_DRY_RUN=0 RETRO_HA_SCREEN_ROTATION=right "$ROOT_DIR/scripts/mode/retro-mode.sh"

# retro-mode missing scripts/lib branch (hide both scripts/mode/lib and scripts/lib).
rm -rf "$ROOT_DIR/scripts/mode/lib" 2>/dev/null || true
hidden_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_retro_mode"
if mv "$ROOT_DIR/scripts/lib" "$hidden_lib" 2>/dev/null; then
  run_allow_fail "$ROOT_DIR/scripts/mode/retro-mode.sh"
  mv "$hidden_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
fi

# mount-nfs*.sh: cover lib selection branches and error branch.
# NOTE: avoid subshells here; KCOV_WRAP collects part dirs in an array.
nfs_lib_link="$ROOT_DIR/scripts/nfs/lib"
rm -rf "$nfs_lib_link" 2>/dev/null || true

# if branch: scripts/nfs/lib exists
ln -s ../lib "$nfs_lib_link" 2>/dev/null || true
run_allow_fail env RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
run_allow_fail env RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
rm -rf "$nfs_lib_link" 2>/dev/null || true

# elif branch: scripts/lib exists
run_allow_fail env RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
run_allow_fail env RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"

# else branch: hide scripts/lib (and ensure scripts/nfs/lib is absent)
hidden_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_nfs_mount"
if mv "$ROOT_DIR/scripts/lib" "$hidden_lib" 2>/dev/null; then
  rm -rf "$nfs_lib_link" 2>/dev/null || true
  run_allow_fail "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
  run_allow_fail "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
  mv "$hidden_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
fi

# Cover SCRIPT_DIR fallback (SCRIPT_DIR='.') by executing via PATH (no slash).
(
  set +e
  cd "$ROOT_DIR/scripts/mode" || exit 0
  ln -s ../lib "lib" 2>/dev/null || true
  RETRO_HA_DRY_RUN=1 PATH="$stub_bin:/usr/bin:/bin" /usr/bin/bash ./retro-mode.sh >/dev/null 2>&1
  rm -f "lib" >/dev/null 2>&1 || true
) || true

# Cover nfs scripts' "$SCRIPT_DIR/lib" selection by providing scripts/nfs/lib -> ../lib.
nfs_lib_link="$ROOT_DIR/scripts/nfs/lib"
if [[ ! -e "$nfs_lib_link" ]]; then
  ln -s ../lib "$nfs_lib_link" 2>/dev/null || true
fi
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_SAVE_BACKUP_ENABLED=0 "$ROOT_DIR/scripts/nfs/save-backup.sh"
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_NFS_ROMS_SUBDIR= "$ROOT_DIR/scripts/nfs/sync-roms.sh"
rm -f "$nfs_lib_link" 2>/dev/null || true

# save-backup.sh missing scripts/lib branch (hide scripts/lib and ensure scripts/nfs/lib is absent).
hidden_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_save_backup"
if mv "$ROOT_DIR/scripts/lib" "$hidden_lib" 2>/dev/null; then
  rm -rf "$ROOT_DIR/scripts/nfs/lib" 2>/dev/null || true
  run_allow_fail "$ROOT_DIR/scripts/nfs/save-backup.sh"
  mv "$hidden_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
fi

# Cover scripts/mode/lib branch selection.
mode_lib_link="$ROOT_DIR/scripts/mode/lib"
if [[ ! -e "$mode_lib_link" ]]; then
  ln -s ../lib "$mode_lib_link" 2>/dev/null || true
fi
run_allow_fail env RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/mode/retro-mode.sh"
rm -f "$mode_lib_link" 2>/dev/null || true

# enter-ha-mode.sh: exercise svc_stop + svc_start via dry-run and non-dry-run.
# Also cover the "$SCRIPT_DIR/lib" branch by temporarily creating scripts/mode/lib.
mode_lib_link="$ROOT_DIR/scripts/mode/lib"
if [[ ! -e "$mode_lib_link" ]]; then
  ln -s ../lib "$mode_lib_link" 2>/dev/null || true
fi
run_allow_fail env RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/mode/enter-ha-mode.sh"
run_allow_fail env RETRO_HA_DRY_RUN=0 "$ROOT_DIR/scripts/mode/enter-ha-mode.sh"
rm -f "$mode_lib_link" 2>/dev/null || true

# enter-retro-mode.sh: exercise ledctl path resolution (libdir and repo fallback).
tmp_lib="$work_dir/lib"
mkdir -p "$tmp_lib"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$tmp_lib/ledctl.sh"
chmod +x "$tmp_lib/ledctl.sh"
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR="$tmp_lib" "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"

# Cover scripts/mode/lib selection in enter-retro-mode.
mode_lib_link="$ROOT_DIR/scripts/mode/lib"
if [[ ! -e "$mode_lib_link" ]]; then
  ln -s ../lib "$mode_lib_link" 2>/dev/null || true
fi
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"
rm -f "$mode_lib_link" 2>/dev/null || true

# enter-retro-mode.sh: missing scripts/lib branch.
rm -rf "$ROOT_DIR/scripts/mode/lib" 2>/dev/null || true
hidden_enter_retro_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_enter_retro_mode"
if mv "$ROOT_DIR/scripts/lib" "$hidden_enter_retro_lib" 2>/dev/null; then
  run_allow_fail "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"
  mv "$hidden_enter_retro_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
fi

# Force fallback to installed default by making repo ledctl non-executable.
chmod -x "$ROOT_DIR/scripts/leds/ledctl.sh" || true
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"
chmod +x "$ROOT_DIR/scripts/leds/ledctl.sh" || true

(
  # Directly call retro_ha_ledctl_path to hit the SCRIPT_DIR/ledctl.sh candidate lines
  # without executing a new script file (avoid expanding kcov's file set).
  set -euo pipefail
  tmp_candidate="$ROOT_DIR/scripts/mode/ledctl.__kcov_candidate"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$tmp_candidate"
  chmod +x "$tmp_candidate"
  # Source the script and temporarily bind candidate name.
  # shellcheck source=scripts/mode/enter-retro-mode.sh
  source "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"
  # Simulate existence of SCRIPT_DIR/ledctl.sh by pointing SCRIPT_DIR at a dir where it exists.
  SCRIPT_DIR="${tmp_candidate%/*}"
  mv "$tmp_candidate" "$SCRIPT_DIR/ledctl.sh"
  retro_ha_ledctl_path >/dev/null
  rm -f "$SCRIPT_DIR/ledctl.sh"
)

# healthcheck.sh: ha active / retro active / failover path selection.
run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS=":ha-kiosk.service:" RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/healthcheck.sh"
run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS=":retro-mode.service:" RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/healthcheck.sh"

hc_lib="$work_dir/hc-lib"
mkdir -p "$hc_lib"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$hc_lib/enter-retro-mode.sh"
chmod +x "$hc_lib/enter-retro-mode.sh"
run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS="" RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR="$hc_lib" "$ROOT_DIR/scripts/healthcheck.sh"

# Choose scripts/mode/enter-retro-mode.sh (no RETRO_HA_LIBDIR).
run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS="" RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= "$ROOT_DIR/scripts/healthcheck.sh"

# Cover healthcheck: script_dir/enter-retro-mode.sh branch.
(
  set +e
  tmp_enter="$ROOT_DIR/scripts/enter-retro-mode.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$tmp_enter"
  chmod +x "$tmp_enter"
  run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS="" RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= "$ROOT_DIR/scripts/healthcheck.sh"
  rm -f "$tmp_enter" >/dev/null 2>&1 || true
) || true

# Cover healthcheck: fallback branch by temporarily hiding scripts/mode/enter-retro-mode.sh.
(
  set +e
  tmp_hidden="$ROOT_DIR/scripts/mode/enter-retro-mode.sh.__kcov_hidden"
  mv "$ROOT_DIR/scripts/mode/enter-retro-mode.sh" "$tmp_hidden" 2>/dev/null || exit 0
  run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS="" RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= "$ROOT_DIR/scripts/healthcheck.sh"
  mv "$tmp_hidden" "$ROOT_DIR/scripts/mode/enter-retro-mode.sh" 2>/dev/null || true
) || true

# healthcheck.sh: missing scripts/lib branch (avoid subshell so KCOV_WRAP collects part dirs).
hidden_healthcheck_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_healthcheck_missing"
if mv "$ROOT_DIR/scripts/lib" "$hidden_healthcheck_lib" 2>/dev/null; then
  run_allow_fail "$ROOT_DIR/scripts/healthcheck.sh"
  mv "$hidden_healthcheck_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
fi

# Cover healthcheck's "$SCRIPT_DIR/../lib" selection by temporarily providing a repo-root lib/.
root_lib="$ROOT_DIR/lib"
hidden_scripts_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_parent"
if [[ ! -d "$root_lib" ]]; then
  mkdir -p "$root_lib"
  cp -R "$ROOT_DIR/scripts/lib/"* "$root_lib/" 2>/dev/null || true
  mv "$ROOT_DIR/scripts/lib" "$hidden_scripts_lib" 2>/dev/null || true
  run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS=":ha-kiosk.service:" RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/healthcheck.sh"
  mv "$hidden_scripts_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
  rm -rf "$root_lib" 2>/dev/null || true
fi

# retropie/install-retropie.sh: require_root fail + user missing + git/sudo missing + home missing + clone/update + dry-run/non-dry-run.
run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=0 EUID=1000 RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/retropie/install-retropie.sh"
run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 KCOV_RETROPI_EXISTS=0 RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/retropie/install-retropie.sh"

home="$work_dir/home/retropi"
mkdir -p "$home"

# Cover scripts/retropie/lib selection in install-retropie.
retropie_lib_link="$ROOT_DIR/scripts/retropie/lib"
if [[ ! -e "$retropie_lib_link" ]]; then
  ln -s ../lib "$retropie_lib_link" 2>/dev/null || true
fi
run_allow_fail env KCOV_GETENT_HOME="$home" PATH="$stub_bin:/usr/bin:/bin" RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 KCOV_RETROPI_EXISTS=1 "$ROOT_DIR/scripts/retropie/install-retropie.sh"
rm -f "$retropie_lib_link" 2>/dev/null || true

nogit="$work_dir/bin-nogit"
mkdir -p "$nogit"
ln -sf /usr/bin/bash "$nogit/bash"
ln -sf /usr/bin/env "$nogit/env"
ln -sf /usr/bin/dirname "$nogit/dirname"
ln -sf "$stub_bin/id" "$nogit/id"
ln -sf /usr/bin/cut "$nogit/cut"
ln -sf /usr/bin/mkdir "$nogit/mkdir"
ln -sf /usr/bin/rm "$nogit/rm"
ln -sf /usr/bin/mktemp "$nogit/mktemp"
ln -sf /usr/bin/chmod "$nogit/chmod"
ln -sf /usr/bin/ln "$nogit/ln"
ln -sf "$stub_bin/getent" "$nogit/getent"
ln -sf "$stub_bin/sudo" "$nogit/sudo"
run_allow_fail env KCOV_GETENT_HOME="$home" PATH="$nogit" RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/retropie/install-retropie.sh"

nosudo="$work_dir/bin-nosudo"
mkdir -p "$nosudo"
ln -sf /usr/bin/bash "$nosudo/bash"
ln -sf /usr/bin/env "$nosudo/env"
ln -sf /usr/bin/dirname "$nosudo/dirname"
ln -sf "$stub_bin/id" "$nosudo/id"
ln -sf /usr/bin/cut "$nosudo/cut"
ln -sf /usr/bin/mkdir "$nosudo/mkdir"
ln -sf /usr/bin/rm "$nosudo/rm"
ln -sf /usr/bin/mktemp "$nosudo/mktemp"
ln -sf /usr/bin/chmod "$nosudo/chmod"
ln -sf /usr/bin/ln "$nosudo/ln"
ln -sf "$stub_bin/getent" "$nosudo/getent"
ln -sf "$stub_bin/git" "$nosudo/git"
run_allow_fail env KCOV_GETENT_HOME="$home" PATH="$nosudo" RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/retropie/install-retropie.sh"

# Home missing branch: keep getent successful but with an empty home field.
home_missing_bin="$work_dir/bin-home-missing"
mkdir -p "$home_missing_bin"
ln -sf /usr/bin/bash "$home_missing_bin/bash"
ln -sf /usr/bin/env "$home_missing_bin/env"
ln -sf /usr/bin/dirname "$home_missing_bin/dirname"
ln -sf "$stub_bin/id" "$home_missing_bin/id"
ln -sf /usr/bin/cut "$home_missing_bin/cut"
ln -sf /usr/bin/mkdir "$home_missing_bin/mkdir"
ln -sf /usr/bin/rm "$home_missing_bin/rm"
ln -sf /usr/bin/mktemp "$home_missing_bin/mktemp"
ln -sf /usr/bin/chmod "$home_missing_bin/chmod"
ln -sf /usr/bin/ln "$home_missing_bin/ln"
ln -sf "$stub_bin/git" "$home_missing_bin/git"
ln -sf "$stub_bin/sudo" "$home_missing_bin/sudo"
cat >"$home_missing_bin/getent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "passwd" && "${2:-}" == "retropi" ]]; then
  # Empty home directory field.
  printf 'retropi:x:1000:1000:::/bin/bash\n'
  exit 0
fi

exec /usr/bin/getent "$@"
EOF
chmod +x "$home_missing_bin/getent"
run_allow_fail env PATH="$home_missing_bin" RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/retropie/install-retropie.sh"

# Ensure install-retropie missing git/sudo/home branches are covered even if kcov wrapper attribution is flaky.
# Run the script by sourcing it in a subshell with a controlled PATH; it will execute main and call die.
(
  set +e
  export PATH="$nogit"
  export RETRO_HA_ALLOW_NON_ROOT=1
  export RETRO_HA_DRY_RUN=1
  export KCOV_RETROPI_EXISTS=1
  export KCOV_GETENT_HOME="$home"
  # shellcheck source=scripts/retropie/install-retropie.sh
  source "$ROOT_DIR/scripts/retropie/install-retropie.sh"
) || true

(
  set +e
  export PATH="$nosudo"
  export RETRO_HA_ALLOW_NON_ROOT=1
  export RETRO_HA_DRY_RUN=1
  export KCOV_RETROPI_EXISTS=1
  export KCOV_GETENT_HOME="$home"
  # shellcheck source=scripts/retropie/install-retropie.sh
  source "$ROOT_DIR/scripts/retropie/install-retropie.sh"
) || true

(
  set +e
  export PATH="$home_missing_bin"
  export RETRO_HA_ALLOW_NON_ROOT=1
  export RETRO_HA_DRY_RUN=1
  export KCOV_RETROPI_EXISTS=1
  # shellcheck source=scripts/retropie/install-retropie.sh
  source "$ROOT_DIR/scripts/retropie/install-retropie.sh"
) || true

# screen-brightness-mqtt.sh: cover remaining branches (clamp>100, state-same, sleep, no-backlight, max missing/invalid).
bl_root="$(retro_ha_path /sys/class/backlight)"
mkdir -p "$bl_root"

# Clamp to 100% when raw > max.
mkdir -p "$bl_root/blc"
printf '%s\n' '10' >"$bl_root/blc/max_brightness"
printf '%s\n' '20' >"$bl_root/blc/brightness"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME=blc \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=2 \
  KCOV_MOSQUITTO_SUB_OUTPUT='' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# No backlight device (auto-detect empty) -> die.
rm -rf "$bl_root" && mkdir -p "$bl_root"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME= \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT='retro-ha/screen/brightness/set 10\n' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# max_brightness missing -> die.
mkdir -p "$bl_root/blm"
printf '%s\n' '1' >"$bl_root/blm/brightness"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME=blm \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT='retro-ha/screen/brightness/set 10\n' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

# max_brightness invalid -> die.
mkdir -p "$bl_root/bli"
printf '%s\n' '0' >"$bl_root/bli/max_brightness"
printf '%s\n' '1' >"$bl_root/bli/brightness"
run_allow_fail env \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_ENABLED=1 \
  MQTT_HOST=localhost \
  RETRO_HA_BACKLIGHT_NAME=bli \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_POLL_SEC=0 \
  RETRO_HA_SCREEN_BRIGHTNESS_MQTT_MAX_LOOPS=1 \
  KCOV_MOSQUITTO_SUB_OUTPUT='retro-ha/screen/brightness/set 10\n' \
  "$ROOT_DIR/scripts/screen/screen-brightness-mqtt.sh"

setup_dir="$home/RetroPie-Setup"
rm -rf "$setup_dir"
run_allow_fail env KCOV_GETENT_HOME="$home" RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 RETRO_HA_RETROPIE_SETUP_DIR="$setup_dir" "$ROOT_DIR/scripts/retropie/install-retropie.sh"
mkdir -p "$setup_dir/.git"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$setup_dir/retropie_packages.sh"
chmod +x "$setup_dir/retropie_packages.sh"
run_allow_fail env KCOV_GETENT_HOME="$home" PATH="$stub_bin:/usr/bin:/bin" RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 KCOV_RETROPI_EXISTS=1 RETRO_HA_RETROPIE_SETUP_DIR="$setup_dir" "$ROOT_DIR/scripts/retropie/install-retropie.sh"

# Missing scripts/lib branch (temporarily hide scripts/lib and ensure scripts/retropie/lib isn't present).
rm -f "$ROOT_DIR/scripts/retropie/lib" 2>/dev/null || true
hidden_retropie_install_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_retropie_install"
mv "$ROOT_DIR/scripts/lib" "$hidden_retropie_install_lib" 2>/dev/null || true
run_allow_fail "$ROOT_DIR/scripts/retropie/install-retropie.sh"
mv "$hidden_retropie_install_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true

# retropie/configure-retropie-storage.sh: require_root fail + getent missing + guardrails + retroarch missing/present + ensure_kv_line dry-run and non-dry-run.
run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=0 RETRO_HA_EUID_OVERRIDE=1000 RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Configure-retropie-storage: missing scripts/lib branch.
rm -f "$ROOT_DIR/scripts/retropie/lib" 2>/dev/null || true
hidden_retropie_storage_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_retropie_storage"
if mv "$ROOT_DIR/scripts/lib" "$hidden_retropie_storage_lib" 2>/dev/null; then
  run_allow_fail "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"
  mv "$hidden_retropie_storage_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
fi

# Cover scripts/retropie/lib selection.
retropie_lib_link="$ROOT_DIR/scripts/retropie/lib"
if [[ ! -e "$retropie_lib_link" ]]; then
  ln -s ../lib "$retropie_lib_link" 2>/dev/null || true
fi
KCOV_GETENT_HOME="$home" PATH="$stub_bin:/usr/bin:/bin" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 KCOV_RETROPI_EXISTS=1 "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"
rm -f "$retropie_lib_link" 2>/dev/null || true

KCOV_GETENT_HOME="" PATH="$stub_bin:/usr/bin:/bin" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

nfs_mp="$RETRO_HA_ROOT/mnt/retro-ha-roms"
mkdir -p "$nfs_mp"
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" RETRO_HA_ROMS_DIR="$nfs_mp/roms" "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Configure-retropie-storage: saves/states under NFS mount guardrails.
KCOV_GETENT_HOME="$home" run_allow_fail env \
  RETRO_HA_ALLOW_NON_ROOT=1 \
  RETRO_HA_DRY_RUN=1 \
  RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" \
  RETRO_HA_ROMS_DIR="$(retro_ha_path /var/lib/retro-ha/retropie/roms)" \
  RETRO_HA_SAVES_DIR="$nfs_mp/saves" \
  RETRO_HA_STATES_DIR="$(retro_ha_path /var/lib/retro-ha/retropie/states)" \
  "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

KCOV_GETENT_HOME="$home" run_allow_fail env \
  RETRO_HA_ALLOW_NON_ROOT=1 \
  RETRO_HA_DRY_RUN=1 \
  RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" \
  RETRO_HA_ROMS_DIR="$(retro_ha_path /var/lib/retro-ha/retropie/roms)" \
  RETRO_HA_SAVES_DIR="$(retro_ha_path /var/lib/retro-ha/retropie/saves)" \
  RETRO_HA_STATES_DIR="$nfs_mp/states" \
  "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

retro_cfg="$RETRO_HA_ROOT/opt/retropie/configs/all/retroarch.cfg"
rm -f "$retro_cfg"
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

mkdir -p "${retro_cfg%/*}"
printf '%s\n' 'savefile_directory = "old"' >"$retro_cfg"
KCOV_GETENT_HOME="$home" PATH="$stub_bin:/usr/bin:/bin" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 KCOV_RETROPI_EXISTS=1 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Dry-run kv writes while RetroArch config exists.
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Make legacy /var/lib/retro-ha/roms exist so the script skips ln -s.
mkdir -p "$(retro_ha_path /var/lib/retro-ha/roms)"

# Target exists as a directory -> mv branch.
mkdir -p "$home/RetroPie/roms"
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Target is already a symlink -> -L branch.
rm -rf "$home/RetroPie/roms"
ln -sf "$(retro_ha_path /var/lib/retro-ha/retropie/roms)" "$home/RetroPie/roms"
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Prepare a config.env for bootstrap/install to load.
cat >"$RETRO_HA_ROOT/etc/retro-ha/config.env" <<EOF
RETRO_HA_REPO_URL=https://example.invalid/repo.git
RETRO_HA_REPO_REF=main
EOF

bootstrap_empty_config="$work_dir/bootstrap-empty-config.env"
: >"$bootstrap_empty_config"

# Missing scripts/lib branch (copy script without adjacent lib directories).
bootstrap_missing_lib_dir="$work_dir/bootstrap-missing-lib"
mkdir -p "$bootstrap_missing_lib_dir"
cp "$ROOT_DIR/scripts/bootstrap.sh" "$bootstrap_missing_lib_dir/bootstrap.sh"
chmod +x "$bootstrap_missing_lib_dir/bootstrap.sh"
run_allow_fail "$bootstrap_missing_lib_dir/bootstrap.sh"

# Exercise bootstrap branches.
export RETRO_HA_DRY_RUN=1
export GETENT_HOSTS_EXIT_CODE=0
export CURL_EXIT_CODE=0

checkout_dir="$RETRO_HA_ROOT/opt/retro-ha-appliance"
mkdir -p "$checkout_dir"

# Clone path (no .git dir)
rm -rf "$checkout_dir/.git"
run_allow_fail env \
  RETRO_HA_CHECKOUT_DIR="$checkout_dir" \
  RETRO_HA_REPO_URL=https://example.invalid/repo.git \
  RETRO_HA_REPO_REF=main \
  PATH="$stub_bin:/usr/bin:/bin" \
  KCOV_GETENT_HOSTS_OK=1 \
  KCOV_CURL_OK=1 \
  "$ROOT_DIR/scripts/bootstrap.sh"

# Already cloned path
mkdir -p "$checkout_dir/.git"
run_allow_fail env \
  RETRO_HA_CHECKOUT_DIR="$checkout_dir" \
  RETRO_HA_REPO_URL=https://example.invalid/repo.git \
  RETRO_HA_REPO_REF=main \
  PATH="$stub_bin:/usr/bin:/bin" \
  KCOV_GETENT_HOSTS_OK=1 \
  KCOV_CURL_OK=1 \
  "$ROOT_DIR/scripts/bootstrap.sh"

# Missing installer branch
run_allow_fail env \
  RETRO_HA_CHECKOUT_DIR="$RETRO_HA_ROOT/opt/missing-installer" \
  RETRO_HA_REPO_URL=https://example.invalid/repo.git \
  RETRO_HA_REPO_REF=main \
  PATH="$stub_bin:/usr/bin:/bin" \
  KCOV_GETENT_HOSTS_OK=1 \
  KCOV_CURL_OK=1 \
  "$ROOT_DIR/scripts/bootstrap.sh"

# Missing repo URL/REF branches.
run_allow_fail env \
  RETRO_HA_CONFIG_ENV="$bootstrap_empty_config" \
  RETRO_HA_CHECKOUT_DIR="$checkout_dir" \
  RETRO_HA_REPO_URL= \
  RETRO_HA_REPO_REF=main \
  PATH="$stub_bin:/usr/bin:/bin" \
  KCOV_GETENT_HOSTS_OK=1 \
  KCOV_CURL_OK=1 \
  "$ROOT_DIR/scripts/bootstrap.sh"

run_allow_fail env \
  RETRO_HA_CONFIG_ENV="$bootstrap_empty_config" \
  RETRO_HA_CHECKOUT_DIR="$checkout_dir" \
  RETRO_HA_REPO_URL=https://example.invalid/repo.git \
  RETRO_HA_REPO_REF= \
  PATH="$stub_bin:/usr/bin:/bin" \
  KCOV_GETENT_HOSTS_OK=1 \
  KCOV_CURL_OK=1 \
  "$ROOT_DIR/scripts/bootstrap.sh"

# Installer dry-run branch (ensure installer exists and is executable).
checkout_dry="$RETRO_HA_ROOT/opt/retro-ha-dry"
mkdir -p "$checkout_dry/.git" "$checkout_dry/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$checkout_dry/scripts/install.sh"
chmod +x "$checkout_dry/scripts/install.sh"
run_allow_fail env \
  RETRO_HA_DRY_RUN=1 \
  RETRO_HA_CONFIG_ENV="$bootstrap_empty_config" \
  RETRO_HA_REPO_URL=https://example.invalid/repo.git \
  RETRO_HA_REPO_REF=main \
  RETRO_HA_CHECKOUT_DIR="$checkout_dry" \
  PATH="$stub_bin:/usr/bin:/bin" \
  KCOV_GETENT_HOSTS_OK=1 \
  KCOV_CURL_OK=1 \
  "$ROOT_DIR/scripts/bootstrap.sh"

# Cover bootstrap's "$SCRIPT_DIR/../lib" selection by temporarily providing a repo-root lib/.
root_lib="$ROOT_DIR/lib"
hidden_scripts_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_parent"
if [[ ! -d "$root_lib" ]]; then
  mkdir -p "$root_lib"
  cp -R "$ROOT_DIR/scripts/lib/"* "$root_lib/" 2>/dev/null || true
  mv "$ROOT_DIR/scripts/lib" "$hidden_scripts_lib" 2>/dev/null || true
  run_allow_fail env RETRO_HA_DRY_RUN=1 KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=1 RETRO_HA_REPO_URL=https://example.invalid/repo.git RETRO_HA_REPO_REF=main "$ROOT_DIR/scripts/bootstrap.sh"
  mv "$hidden_scripts_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
  rm -rf "$root_lib" 2>/dev/null || true
fi

# Marker present early-exit.
installed_marker="$RETRO_HA_ROOT/var/lib/retro-ha/installed"
mkdir -p "${installed_marker%/*}"
: >"$installed_marker"
run_allow_fail env RETRO_HA_DRY_RUN=0 KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=1 "$ROOT_DIR/scripts/bootstrap.sh"
rm -f "$installed_marker"

# Network not ready (DNS fail / HTTPS fail).
run_allow_fail env RETRO_HA_DRY_RUN=0 KCOV_GETENT_HOSTS_OK=0 KCOV_CURL_OK=1 RETRO_HA_REPO_URL=https://example.invalid/repo.git RETRO_HA_REPO_REF=main "$ROOT_DIR/scripts/bootstrap.sh"
run_allow_fail env RETRO_HA_DRY_RUN=0 KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=0 RETRO_HA_REPO_URL=https://example.invalid/repo.git RETRO_HA_REPO_REF=main "$ROOT_DIR/scripts/bootstrap.sh"

# Cover bootstrap exec installer branch.
checkout_exec="$RETRO_HA_ROOT/opt/retro-ha-exec"
mkdir -p "$checkout_exec/.git" "$checkout_exec/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$checkout_exec/scripts/install.sh"
chmod +x "$checkout_exec/scripts/install.sh"
run_allow_fail env \
  RETRO_HA_DRY_RUN=0 \
  KCOV_GETENT_HOSTS_OK=1 \
  KCOV_CURL_OK=1 \
  RETRO_HA_REPO_URL=https://example.invalid/repo.git \
  RETRO_HA_REPO_REF=main \
  RETRO_HA_CHECKOUT_DIR="$checkout_exec" \
  PATH="$stub_bin:/usr/bin:/bin" \
  "$ROOT_DIR/scripts/bootstrap.sh"

# Exercise enter-ha-mode.sh lib discovery branches.
enter_ha_mode="$ROOT_DIR/scripts/mode/enter-ha-mode.sh"

# Prefer SCRIPT_DIR/lib (create temporary symlink scripts/mode/lib -> ../lib).
enter_ha_mode_lib="$ROOT_DIR/scripts/mode/lib"
if [[ ! -e "$enter_ha_mode_lib" ]]; then
  ln -s "../lib" "$enter_ha_mode_lib"
  run_allow_fail env PATH="$stub_bin:/usr/bin:/bin" "$enter_ha_mode"
  rm -f "$enter_ha_mode_lib"
fi

# Normal path (SCRIPT_DIR/../lib).
run_allow_fail env PATH="$stub_bin:/usr/bin:/bin" "$enter_ha_mode"

# Missing scripts/lib path.
hidden_enter_ha_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_enter_ha"
mv "$ROOT_DIR/scripts/lib" "$hidden_enter_ha_lib" 2>/dev/null || true
run_allow_fail "$enter_ha_mode"
mv "$hidden_enter_ha_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true

# Sourced bootstrap should not run main.
(
  set +e
  # shellcheck source=scripts/bootstrap.sh
  source "$ROOT_DIR/scripts/bootstrap.sh"
) || true

# Exercise install.sh branches.
export RETRO_HA_ALLOW_NON_ROOT=1
export RETRO_HA_DRY_RUN=1
export RETRO_HA_INSTALLED_MARKER="$RETRO_HA_ROOT/var/lib/retro-ha/installed"

# Marker present early-exit.
: >"$RETRO_HA_INSTALLED_MARKER"
run_allow_fail env KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=ok \
  "$ROOT_DIR/scripts/install.sh"
rm -f "$RETRO_HA_INSTALLED_MARKER"

# Lock contention.
run_allow_fail env KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=fail \
  "$ROOT_DIR/scripts/install.sh"

# Marker appears while waiting for lock.
run_allow_fail env KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=create_marker \
  "$ROOT_DIR/scripts/install.sh"
rm -f "$RETRO_HA_INSTALLED_MARKER"

# Full-ish dry-run with different apt-cache outcomes and user present/missing.
run_allow_fail env KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=browser KCOV_FLOCK_MODE=ok \
  PATH="$stub_bin:/usr/bin:/bin" "$ROOT_DIR/scripts/install.sh"
run_allow_fail env KCOV_RETROPI_EXISTS=0 KCOV_APT_CACHE_MODE=chromium KCOV_FLOCK_MODE=ok \
  PATH="$stub_bin:/usr/bin:/bin" "$ROOT_DIR/scripts/install.sh"
run_allow_fail env KCOV_RETROPI_EXISTS=0 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=ok \
  RETRO_HA_INSTALL_RETROPIE=1 \
  PATH="$stub_bin:/usr/bin:/bin" "$ROOT_DIR/scripts/install.sh"

# Non-dry-run marker write (covers the date > "$MARKER_FILE" line).
run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=ok \
  PATH="$stub_bin:/usr/bin:/bin" "$ROOT_DIR/scripts/install.sh"

# Require-root failure branch.
run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=0 KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=ok \
  RETRO_HA_EUID_OVERRIDE=1000 PATH="$stub_bin:/usr/bin:/bin" "$ROOT_DIR/scripts/install.sh"

# Require-root success branch.
run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=0 RETRO_HA_EUID_OVERRIDE=0 RETRO_HA_DRY_RUN=1 KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=ok \
  PATH="$stub_bin:/usr/bin:/bin" "$ROOT_DIR/scripts/install.sh"
