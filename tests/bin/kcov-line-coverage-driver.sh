#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

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

# Minimal curl stub.
# KCOV_CURL_OK=1 -> succeed, else fail.
if [[ "${KCOV_CURL_OK:-1}" == "1" ]]; then
  exit 0
fi
exit 22
EOF
chmod +x "$stub_bin/curl"

cat >"$stub_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal sudo stub for driver coverage.
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

# Minimal git stub for driver coverage.
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

# Minimal id stub for driver coverage.
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
# shellcheck source=scripts/lib/logging.sh
source "$ROOT_DIR/scripts/lib/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$ROOT_DIR/scripts/lib/config.sh"

# Hit remaining uncovered lines in logging.sh.
warn "driver warn"

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
  (
    set +e
    bash "$ROOT_DIR/scripts/bootstrap.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/healthcheck.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/install.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/leds/ledctl.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/leds/led-mqtt.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/mode/enter-ha-mode.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/mode/enter-retro-mode.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/mode/ha-kiosk.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/mode/retro-mode.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/nfs/mount-nfs.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/nfs/save-backup.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/nfs/sync-roms.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh" >/dev/null 2>&1
    bash "$ROOT_DIR/scripts/retropie/install-retropie.sh" >/dev/null 2>&1
  ) || true
  mv "$hidden_lib_dir" "$lib_dir"
fi

run_allow_fail() {
  set +e
  "$@" >/dev/null 2>&1
  set -e
}

export RETRO_HA_ROOT="$work_dir/root"
mkdir -p "$RETRO_HA_ROOT"

# Fake LED sysfs so ledctl can fully exercise success paths.
mkdir -p "$RETRO_HA_ROOT/sys/class/leds/led0" "$RETRO_HA_ROOT/sys/class/leds/led1"
echo 'none [mmc0] timer heartbeat' >"$RETRO_HA_ROOT/sys/class/leds/led0/trigger"
echo 0 >"$RETRO_HA_ROOT/sys/class/leds/led0/brightness"
echo 'none [default-on] timer heartbeat' >"$RETRO_HA_ROOT/sys/class/leds/led1/trigger"
echo 0 >"$RETRO_HA_ROOT/sys/class/leds/led1/brightness"

# ledctl.sh: usage + invalid inputs + missing sysfs + supported/unsupported triggers.
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh"
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh" bad on
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh" act bad
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh" act off
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh" act on
run_allow_fail env RETRO_HA_ACT_LED_TRIGGER_ON=nonesuch bash "$ROOT_DIR/scripts/leds/ledctl.sh" act on
run_allow_fail env RETRO_HA_ACT_LED=missing-led bash "$ROOT_DIR/scripts/leds/ledctl.sh" act off
run_allow_fail env RETRO_HA_ACT_LED=missing-led bash "$ROOT_DIR/scripts/leds/ledctl.sh" act on
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh" pwr off
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh" pwr on
run_allow_fail env RETRO_HA_PWR_LED_TRIGGER_ON=nonesuch bash "$ROOT_DIR/scripts/leds/ledctl.sh" pwr on
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh" all on
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh" all off

# Cover scripts/leds/lib branch selection.
leds_lib_link="$ROOT_DIR/scripts/leds/lib"
if [[ ! -e "$leds_lib_link" ]]; then
  ln -s ../lib "$leds_lib_link" 2>/dev/null || true
fi
run_allow_fail bash "$ROOT_DIR/scripts/leds/ledctl.sh" act off
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
run_allow_fail env NFS_SERVER= NFS_PATH= bash "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
run_allow_fail env NFS_SERVER=server NFS_PATH=/export KCOV_MOUNTPOINTS_MOUNTED=":${mp_roms}:" bash "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
run_allow_fail env NFS_SERVER=server NFS_PATH=/export RETRO_HA_NFS_MOUNT_POINT="$mp_roms" KCOV_MOUNTPOINTS_MOUNTED="" KCOV_MOUNT_FAIL=1 bash "$ROOT_DIR/scripts/nfs/mount-nfs.sh"
run_allow_fail env NFS_SERVER=server NFS_PATH=/export RETRO_HA_NFS_MOUNT_POINT="$mp_roms" KCOV_MOUNTPOINTS_MOUNTED="" KCOV_MOUNT_FAIL=0 bash "$ROOT_DIR/scripts/nfs/mount-nfs.sh"

# mount-nfs-backup.sh: disabled / not configured / already mounted / mount fail / mount success.
backup_root="$RETRO_HA_ROOT/mnt/retro-ha-backup"
mkdir -p "$backup_root"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=0 bash "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_NFS_SERVER= RETRO_HA_SAVE_BACKUP_NFS_PATH= bash "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_NFS_SERVER=server RETRO_HA_SAVE_BACKUP_NFS_PATH=/export RETRO_HA_SAVE_BACKUP_DIR="$backup_root" KCOV_MOUNTPOINTS_MOUNTED=":${backup_root}:" bash "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_NFS_SERVER=server RETRO_HA_SAVE_BACKUP_NFS_PATH=/export RETRO_HA_SAVE_BACKUP_DIR="$backup_root" KCOV_MOUNTPOINTS_MOUNTED="" KCOV_MOUNT_FAIL=1 bash "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_NFS_SERVER=server RETRO_HA_SAVE_BACKUP_NFS_PATH=/export RETRO_HA_SAVE_BACKUP_DIR="$backup_root" KCOV_MOUNTPOINTS_MOUNTED="" KCOV_MOUNT_FAIL=0 bash "$ROOT_DIR/scripts/nfs/mount-nfs-backup.sh"
rm -f "$nfs_lib_link" 2>/dev/null || true

# save-backup.sh: disabled / retro active / not mounted / rsync missing / backup saves+states (delete on).
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=0 bash "$ROOT_DIR/scripts/nfs/save-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 KCOV_SYSTEMCTL_ACTIVE_UNITS=":retro-mode.service:" bash "$ROOT_DIR/scripts/nfs/save-backup.sh"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 KCOV_SYSTEMCTL_ACTIVE_UNITS="" KCOV_MOUNTPOINTS_MOUNTED="" bash "$ROOT_DIR/scripts/nfs/save-backup.sh"

mv "$stub_bin/rsync" "$stub_bin/rsync.__kcov_hidden"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 KCOV_SYSTEMCTL_ACTIVE_UNITS="" KCOV_MOUNTPOINTS_MOUNTED=":${backup_root}:" bash "$ROOT_DIR/scripts/nfs/save-backup.sh"
mv "$stub_bin/rsync.__kcov_hidden" "$stub_bin/rsync"

mkdir -p "$RETRO_HA_ROOT/var/lib/retro-ha/retropie/saves" "$RETRO_HA_ROOT/var/lib/retro-ha/retropie/states"
run_allow_fail env RETRO_HA_SAVE_BACKUP_ENABLED=1 RETRO_HA_SAVE_BACKUP_DIR="$backup_root" RETRO_HA_SAVE_BACKUP_DELETE=1 KCOV_SYSTEMCTL_ACTIVE_UNITS="" KCOV_MOUNTPOINTS_MOUNTED=":${backup_root}:" bash "$ROOT_DIR/scripts/nfs/save-backup.sh"

# sync-roms.sh: rsync missing / not mounted / src missing / allowlist+missing system / excluded / discover + delete.
mp_src="$mp_roms"
src_subdir="roms"
mkdir -p "$mp_src/$src_subdir/nes" "$mp_src/$src_subdir/snes"

mv "$stub_bin/rsync" "$stub_bin/rsync.__kcov_hidden"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" bash "$ROOT_DIR/scripts/nfs/sync-roms.sh"
mv "$stub_bin/rsync.__kcov_hidden" "$stub_bin/rsync"

run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" KCOV_MOUNTPOINTS_MOUNTED="" bash "$ROOT_DIR/scripts/nfs/sync-roms.sh"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR=missing KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" bash "$ROOT_DIR/scripts/nfs/sync-roms.sh"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" RETRO_HA_ROMS_SYSTEMS="missing" KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" bash "$ROOT_DIR/scripts/nfs/sync-roms.sh"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" RETRO_HA_ROMS_SYSTEMS="nes,snes" RETRO_HA_ROMS_EXCLUDE_SYSTEMS="nes" KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" bash "$ROOT_DIR/scripts/nfs/sync-roms.sh"
run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" RETRO_HA_ROMS_SYNC_DELETE=1 KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" bash "$ROOT_DIR/scripts/nfs/sync-roms.sh"

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
PATH="$no_chown" run_allow_fail env RETRO_HA_NFS_MOUNT_POINT="$mp_src" RETRO_HA_NFS_ROMS_SUBDIR="$src_subdir" KCOV_MOUNTPOINTS_MOUNTED=":${mp_src}:" bash "$ROOT_DIR/scripts/nfs/sync-roms.sh"

# led-mqtt.sh: disabled / missing host / missing ledctl / payload handling + state publish + tls/user/pass.
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=0 bash "$ROOT_DIR/scripts/leds/led-mqtt.sh"
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST= bash "$ROOT_DIR/scripts/leds/led-mqtt.sh"
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST=localhost RETRO_HA_LEDCTL_PATH="$work_dir/missing-ledctl" KCOV_MOSQUITTO_SUB_OUTPUT=$'retro-ha/led/act/set ON\n' bash "$ROOT_DIR/scripts/leds/led-mqtt.sh"
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST=localhost MQTT_USERNAME=u MQTT_PASSWORD=p MQTT_TLS=1 RETRO_HA_LEDCTL_PATH="$ROOT_DIR/scripts/leds/ledctl.sh" KCOV_MOSQUITTO_SUB_OUTPUT=$'retro-ha/led/act/set ON\nretro-ha/led/pwr/set off\nretro-ha/led/all/set INVALID\nretro-ha/led/all/set OFF\nretro-ha/led/bad/set ON\n' bash "$ROOT_DIR/scripts/leds/led-mqtt.sh"
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST=localhost MQTT_TLS=0 RETRO_HA_LEDCTL_PATH="$ROOT_DIR/scripts/leds/ledctl.sh" KCOV_MOSQUITTO_SUB_OUTPUT='' bash "$ROOT_DIR/scripts/leds/led-mqtt.sh"

# Cover scripts/leds/lib branch selection in led-mqtt.
leds_lib_link="$ROOT_DIR/scripts/leds/lib"
if [[ ! -e "$leds_lib_link" ]]; then
  ln -s ../lib "$leds_lib_link" 2>/dev/null || true
fi
run_allow_fail env RETRO_HA_LED_MQTT_ENABLED=1 MQTT_HOST=localhost RETRO_HA_LEDCTL_PATH="$ROOT_DIR/scripts/leds/ledctl.sh" KCOV_MOSQUITTO_SUB_OUTPUT=$'retro-ha/led/act/set OFF\n' bash "$ROOT_DIR/scripts/leds/led-mqtt.sh"
rm -f "$leds_lib_link" 2>/dev/null || true

# ha-kiosk.sh: missing HA_URL / missing chromium / dry-run / non-dry-run (exec xinit stub).
run_allow_fail env HA_URL= bash "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
run_allow_fail env HA_URL=http://example.invalid PATH="$stub_bin:/bin" bash "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 RETRO_HA_SCREEN_ROTATION=left bash "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=0 RETRO_HA_SCREEN_ROTATION=left bash "$ROOT_DIR/scripts/mode/ha-kiosk.sh"

# Cover SCRIPT_DIR fallback (SCRIPT_DIR='.') by executing via PATH (no slash).
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 PATH="$ROOT_DIR/scripts/mode:$PATH" ha-kiosk.sh

# Cover scripts/mode/lib branch selection.
mode_lib_link="$ROOT_DIR/scripts/mode/lib"
if [[ ! -e "$mode_lib_link" ]]; then
  ln -s ../lib "$mode_lib_link" 2>/dev/null || true
fi
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/mode/ha-kiosk.sh"

# Ensure chromium_bin chooses chromium (not chromium-browser).
mv "$stub_bin/chromium-browser" "$stub_bin/chromium-browser.__kcov_hidden" 2>/dev/null || true
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
mv "$stub_bin/chromium-browser.__kcov_hidden" "$stub_bin/chromium-browser" 2>/dev/null || true

rm -f "$mode_lib_link" 2>/dev/null || true

# Missing chromium/chromium-browser branch.
no_chromium="$work_dir/bin-no-chromium"
mkdir -p "$no_chromium"
ln -sf /usr/bin/bash "$no_chromium/bash"
ln -sf /usr/bin/id "$no_chromium/id"
ln -sf /usr/bin/mkdir "$no_chromium/mkdir"
ln -sf /usr/bin/chmod "$no_chromium/chmod"
ln -sf /usr/bin/rm "$no_chromium/rm"
ln -sf /usr/bin/cat "$no_chromium/cat"
ln -sf /usr/bin/tr "$no_chromium/tr"
ln -sf "$stub_bin/xinit" "$no_chromium/xinit"
ln -sf "$stub_bin/xset" "$no_chromium/xset"
ln -sf "$stub_bin/xrandr" "$no_chromium/xrandr"
PATH="$no_chromium" run_allow_fail env HA_URL=http://example.invalid bash "$ROOT_DIR/scripts/mode/ha-kiosk.sh"

# Force chromium selection (hide chromium-browser).
mv "$stub_bin/chromium-browser" "$stub_bin/chromium-browser.__kcov_hidden"
run_allow_fail env HA_URL=http://example.invalid RETRO_HA_DRY_RUN=0 RETRO_HA_SCREEN_ROTATION= bash "$ROOT_DIR/scripts/mode/ha-kiosk.sh"
mv "$stub_bin/chromium-browser.__kcov_hidden" "$stub_bin/chromium-browser"

# Reliably cover SCRIPT_DIR fallback (SCRIPT_DIR='.') and the chromium (not chromium-browser) branch.
# Important: run as `bash ha-kiosk.sh` (no slash) so BASH_SOURCE[0] has no '/'.
(
  set +e
  cd "$ROOT_DIR/scripts/mode" || exit 0
  ln -s ../lib "lib" 2>/dev/null || true

  chromium_only="$work_dir/bin-chromium-only"
  mkdir -p "$chromium_only"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$chromium_only/chromium"
  chmod +x "$chromium_only/chromium"

  # Force chromium selection: provide chromium in PATH, and *do not* include /usr/bin
  # (so we don't accidentally find a system chromium-browser first).
  HA_URL=http://example.invalid RETRO_HA_DRY_RUN=1 PATH="$chromium_only:$stub_bin:/bin" /usr/bin/bash ./ha-kiosk.sh >/dev/null 2>&1
  rm -f "lib" >/dev/null 2>&1 || true
) || true

# retro-mode.sh: missing xinit / missing emulationstation / dry-run / non-dry-run.
run_allow_fail env PATH="$stub_bin:/bin" bash "$ROOT_DIR/scripts/mode/retro-mode.sh"

mv "$stub_bin/xinit" "$stub_bin/xinit.__kcov_hidden"
run_allow_fail env RETRO_HA_DRY_RUN=0 bash "$ROOT_DIR/scripts/mode/retro-mode.sh"
mv "$stub_bin/xinit.__kcov_hidden" "$stub_bin/xinit"

mv "$stub_bin/emulationstation" "$stub_bin/emulationstation.__kcov_hidden"
run_allow_fail env RETRO_HA_DRY_RUN=0 bash "$ROOT_DIR/scripts/mode/retro-mode.sh"
mv "$stub_bin/emulationstation.__kcov_hidden" "$stub_bin/emulationstation"
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_SCREEN_ROTATION=right bash "$ROOT_DIR/scripts/mode/retro-mode.sh"
run_allow_fail env RETRO_HA_DRY_RUN=0 RETRO_HA_SCREEN_ROTATION=right bash "$ROOT_DIR/scripts/mode/retro-mode.sh"

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
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_SAVE_BACKUP_ENABLED=0 bash "$ROOT_DIR/scripts/nfs/save-backup.sh"
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_NFS_ROMS_SUBDIR= bash "$ROOT_DIR/scripts/nfs/sync-roms.sh"
rm -f "$nfs_lib_link" 2>/dev/null || true

# Cover scripts/mode/lib branch selection.
mode_lib_link="$ROOT_DIR/scripts/mode/lib"
if [[ ! -e "$mode_lib_link" ]]; then
  ln -s ../lib "$mode_lib_link" 2>/dev/null || true
fi
run_allow_fail env RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/mode/retro-mode.sh"
rm -f "$mode_lib_link" 2>/dev/null || true

# enter-ha-mode.sh: exercise svc_stop + svc_start via dry-run and non-dry-run.
# Also cover the "$SCRIPT_DIR/lib" branch by temporarily creating scripts/mode/lib.
mode_lib_link="$ROOT_DIR/scripts/mode/lib"
if [[ ! -e "$mode_lib_link" ]]; then
  ln -s ../lib "$mode_lib_link" 2>/dev/null || true
fi
run_allow_fail env RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/mode/enter-ha-mode.sh"
run_allow_fail env RETRO_HA_DRY_RUN=0 bash "$ROOT_DIR/scripts/mode/enter-ha-mode.sh"
rm -f "$mode_lib_link" 2>/dev/null || true

# enter-retro-mode.sh: exercise ledctl path resolution (libdir and repo fallback).
tmp_lib="$work_dir/lib"
mkdir -p "$tmp_lib"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$tmp_lib/ledctl.sh"
chmod +x "$tmp_lib/ledctl.sh"
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR="$tmp_lib" bash "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= bash "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"

# Cover scripts/mode/lib selection in enter-retro-mode.
mode_lib_link="$ROOT_DIR/scripts/mode/lib"
if [[ ! -e "$mode_lib_link" ]]; then
  ln -s ../lib "$mode_lib_link" 2>/dev/null || true
fi
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= bash "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"
rm -f "$mode_lib_link" 2>/dev/null || true

# Force fallback to installed default by making repo ledctl non-executable.
chmod -x "$ROOT_DIR/scripts/leds/ledctl.sh" || true
run_allow_fail env RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= bash "$ROOT_DIR/scripts/mode/enter-retro-mode.sh"
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
run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS=":ha-kiosk.service:" RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/healthcheck.sh"
run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS=":retro-mode.service:" RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/healthcheck.sh"

hc_lib="$work_dir/hc-lib"
mkdir -p "$hc_lib"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$hc_lib/enter-retro-mode.sh"
chmod +x "$hc_lib/enter-retro-mode.sh"
run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS="" RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR="$hc_lib" bash "$ROOT_DIR/scripts/healthcheck.sh"

# Choose scripts/mode/enter-retro-mode.sh (no RETRO_HA_LIBDIR).
run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS="" RETRO_HA_DRY_RUN=1 RETRO_HA_LIBDIR= bash "$ROOT_DIR/scripts/healthcheck.sh"

# Cover healthcheck's "$SCRIPT_DIR/../lib" selection by temporarily providing a repo-root lib/.
root_lib="$ROOT_DIR/lib"
hidden_scripts_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_parent"
if [[ ! -d "$root_lib" ]]; then
  mkdir -p "$root_lib"
  cp -R "$ROOT_DIR/scripts/lib/"* "$root_lib/" 2>/dev/null || true
  mv "$ROOT_DIR/scripts/lib" "$hidden_scripts_lib" 2>/dev/null || true
  run_allow_fail env KCOV_SYSTEMCTL_ACTIVE_UNITS=":ha-kiosk.service:" RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/healthcheck.sh"
  mv "$hidden_scripts_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
  rm -rf "$root_lib" 2>/dev/null || true
fi

# retropie/install-retropie.sh: require_root fail + user missing + git/sudo missing + home missing + clone/update + dry-run/non-dry-run.
run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=0 RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/retropie/install-retropie.sh"
run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 KCOV_RETROPI_EXISTS=0 RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/retropie/install-retropie.sh"

home="$work_dir/home/retropi"
mkdir -p "$home"

# Cover scripts/retropie/lib selection in install-retropie.
retropie_lib_link="$ROOT_DIR/scripts/retropie/lib"
if [[ ! -e "$retropie_lib_link" ]]; then
  ln -s ../lib "$retropie_lib_link" 2>/dev/null || true
fi
KCOV_GETENT_HOME="$home" PATH="$stub_bin:/usr/bin:/bin" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 KCOV_RETROPI_EXISTS=1 bash "$ROOT_DIR/scripts/retropie/install-retropie.sh"
rm -f "$retropie_lib_link" 2>/dev/null || true

nogit="$work_dir/bin-nogit"
mkdir -p "$nogit"
ln -sf /usr/bin/bash "$nogit/bash"
ln -sf /usr/bin/id "$nogit/id"
ln -sf /usr/bin/cut "$nogit/cut"
ln -sf "$stub_bin/getent" "$nogit/getent"
ln -sf "$stub_bin/sudo" "$nogit/sudo"
KCOV_GETENT_HOME="$home" PATH="$nogit" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/retropie/install-retropie.sh"

nosudo="$work_dir/bin-nosudo"
mkdir -p "$nosudo"
ln -sf /usr/bin/bash "$nosudo/bash"
ln -sf /usr/bin/id "$nosudo/id"
ln -sf /usr/bin/cut "$nosudo/cut"
ln -sf "$stub_bin/getent" "$nosudo/getent"
ln -sf "$stub_bin/git" "$nosudo/git"
KCOV_GETENT_HOME="$home" PATH="$nosudo" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/retropie/install-retropie.sh"

KCOV_GETENT_HOME="" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/retropie/install-retropie.sh"

setup_dir="$home/RetroPie-Setup"
rm -rf "$setup_dir"
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 RETRO_HA_RETROPIE_SETUP_DIR="$setup_dir" bash "$ROOT_DIR/scripts/retropie/install-retropie.sh"
mkdir -p "$setup_dir/.git"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$setup_dir/retropie_packages.sh"
chmod +x "$setup_dir/retropie_packages.sh"
KCOV_GETENT_HOME="$home" PATH="$stub_bin:/usr/bin:/bin" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 KCOV_RETROPI_EXISTS=1 RETRO_HA_RETROPIE_SETUP_DIR="$setup_dir" bash "$ROOT_DIR/scripts/retropie/install-retropie.sh"

# retropie/configure-retropie-storage.sh: require_root fail + getent missing + guardrails + retroarch missing/present + ensure_kv_line dry-run and non-dry-run.
run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=0 RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Cover scripts/retropie/lib selection.
retropie_lib_link="$ROOT_DIR/scripts/retropie/lib"
if [[ ! -e "$retropie_lib_link" ]]; then
  ln -s ../lib "$retropie_lib_link" 2>/dev/null || true
fi
KCOV_GETENT_HOME="$home" PATH="$stub_bin:/usr/bin:/bin" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 KCOV_RETROPI_EXISTS=1 bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"
rm -f "$retropie_lib_link" 2>/dev/null || true

KCOV_GETENT_HOME="" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

nfs_mp="$RETRO_HA_ROOT/mnt/retro-ha-roms"
mkdir -p "$nfs_mp"
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" RETRO_HA_ROMS_DIR="$nfs_mp/roms" bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

retro_cfg="$RETRO_HA_ROOT/opt/retropie/configs/all/retroarch.cfg"
rm -f "$retro_cfg"
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

mkdir -p "${retro_cfg%/*}"
printf '%s\n' 'savefile_directory = "old"' >"$retro_cfg"
KCOV_GETENT_HOME="$home" PATH="$stub_bin:/usr/bin:/bin" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 KCOV_RETROPI_EXISTS=1 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Dry-run kv writes while RetroArch config exists.
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=1 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Make legacy /var/lib/retro-ha/roms exist so the script skips ln -s.
mkdir -p "$(retro_ha_path /var/lib/retro-ha/roms)"

# Target exists as a directory -> mv branch.
mkdir -p "$home/RetroPie/roms"
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Target is already a symlink -> -L branch.
rm -rf "$home/RetroPie/roms"
ln -sf "$(retro_ha_path /var/lib/retro-ha/retropie/roms)" "$home/RetroPie/roms"
KCOV_GETENT_HOME="$home" run_allow_fail env RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 RETRO_HA_NFS_MOUNT_POINT="$nfs_mp" bash "$ROOT_DIR/scripts/retropie/configure-retropie-storage.sh"

# Prepare a config.env for bootstrap/install to load.
cat >"$RETRO_HA_ROOT/etc/retro-ha/config.env" <<EOF
RETRO_HA_REPO_URL=https://example.invalid/repo.git
RETRO_HA_REPO_REF=main
EOF

# Exercise bootstrap branches.
export RETRO_HA_DRY_RUN=1
export GETENT_HOSTS_EXIT_CODE=0
export CURL_EXIT_CODE=0

checkout_dir="$RETRO_HA_ROOT/opt/retro-ha-appliance"
mkdir -p "$checkout_dir"

# Clone path (no .git dir)
rm -rf "$checkout_dir/.git"
(
  set +e
  RETRO_HA_CHECKOUT_DIR="$checkout_dir" \
    RETRO_HA_REPO_URL=https://example.invalid/repo.git \
    RETRO_HA_REPO_REF=main \
    PATH="$stub_bin:/usr/bin:/bin" KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=1 bash "$ROOT_DIR/scripts/bootstrap.sh" >/dev/null 2>&1
) || true

# Already cloned path
mkdir -p "$checkout_dir/.git"
(
  set +e
  RETRO_HA_CHECKOUT_DIR="$checkout_dir" \
    RETRO_HA_REPO_URL=https://example.invalid/repo.git \
    RETRO_HA_REPO_REF=main \
    PATH="$stub_bin:/usr/bin:/bin" KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=1 bash "$ROOT_DIR/scripts/bootstrap.sh" >/dev/null 2>&1
) || true

# Missing installer branch
(
  set +e
  RETRO_HA_CHECKOUT_DIR="$RETRO_HA_ROOT/opt/missing-installer" \
    RETRO_HA_REPO_URL=https://example.invalid/repo.git \
    RETRO_HA_REPO_REF=main \
    PATH="$stub_bin:/usr/bin:/bin" KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=1 bash "$ROOT_DIR/scripts/bootstrap.sh" >/dev/null 2>&1
) || true

# Cover bootstrap's "$SCRIPT_DIR/../lib" selection by temporarily providing a repo-root lib/.
root_lib="$ROOT_DIR/lib"
hidden_scripts_lib="$ROOT_DIR/scripts/lib.__kcov_hidden_for_parent"
if [[ ! -d "$root_lib" ]]; then
  mkdir -p "$root_lib"
  cp -R "$ROOT_DIR/scripts/lib/"* "$root_lib/" 2>/dev/null || true
  mv "$ROOT_DIR/scripts/lib" "$hidden_scripts_lib" 2>/dev/null || true
  run_allow_fail env RETRO_HA_DRY_RUN=1 KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=1 RETRO_HA_REPO_URL=https://example.invalid/repo.git RETRO_HA_REPO_REF=main bash "$ROOT_DIR/scripts/bootstrap.sh"
  mv "$hidden_scripts_lib" "$ROOT_DIR/scripts/lib" 2>/dev/null || true
  rm -rf "$root_lib" 2>/dev/null || true
fi

# Marker present early-exit.
installed_marker="$RETRO_HA_ROOT/var/lib/retro-ha/installed"
mkdir -p "${installed_marker%/*}"
: >"$installed_marker"
run_allow_fail env RETRO_HA_DRY_RUN=0 KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=1 bash "$ROOT_DIR/scripts/bootstrap.sh"
rm -f "$installed_marker"

# Network not ready (DNS fail / HTTPS fail).
run_allow_fail env RETRO_HA_DRY_RUN=0 KCOV_GETENT_HOSTS_OK=0 KCOV_CURL_OK=1 RETRO_HA_REPO_URL=https://example.invalid/repo.git RETRO_HA_REPO_REF=main bash "$ROOT_DIR/scripts/bootstrap.sh"
run_allow_fail env RETRO_HA_DRY_RUN=0 KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=0 RETRO_HA_REPO_URL=https://example.invalid/repo.git RETRO_HA_REPO_REF=main bash "$ROOT_DIR/scripts/bootstrap.sh"

# Cover bootstrap exec installer branch.
(
  set +e
  checkout_exec="$RETRO_HA_ROOT/opt/retro-ha-exec"
  mkdir -p "$checkout_exec/.git" "$checkout_exec/scripts"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$checkout_exec/scripts/install.sh"
  chmod +x "$checkout_exec/scripts/install.sh"
  RETRO_HA_DRY_RUN=0 KCOV_GETENT_HOSTS_OK=1 KCOV_CURL_OK=1 \
    RETRO_HA_REPO_URL=https://example.invalid/repo.git \
    RETRO_HA_REPO_REF=main \
    RETRO_HA_CHECKOUT_DIR="$checkout_exec" \
    PATH="$stub_bin:/usr/bin:/bin" bash "$ROOT_DIR/scripts/bootstrap.sh" >/dev/null 2>&1
) || true

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
(
  set +e
  KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=ok \
    "$ROOT_DIR/scripts/install.sh" >/dev/null 2>&1
) || true
rm -f "$RETRO_HA_INSTALLED_MARKER"

# Lock contention.
(
  set +e
  KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=fail \
    "$ROOT_DIR/scripts/install.sh" >/dev/null 2>&1
) || true

# Marker appears while waiting for lock.
(
  set +e
  KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=create_marker \
    "$ROOT_DIR/scripts/install.sh" >/dev/null 2>&1
) || true
rm -f "$RETRO_HA_INSTALLED_MARKER"

# Full-ish dry-run with different apt-cache outcomes and user present/missing.
(
  KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=browser KCOV_FLOCK_MODE=ok \
    PATH="$stub_bin:/usr/bin:/bin" bash "$ROOT_DIR/scripts/install.sh" >/dev/null 2>&1
)
(
  KCOV_RETROPI_EXISTS=0 KCOV_APT_CACHE_MODE=chromium KCOV_FLOCK_MODE=ok \
    PATH="$stub_bin:/usr/bin:/bin" bash "$ROOT_DIR/scripts/install.sh" >/dev/null 2>&1
)
(
  KCOV_RETROPI_EXISTS=0 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=ok \
    RETRO_HA_INSTALL_RETROPIE=1 \
    PATH="$stub_bin:/usr/bin:/bin" bash "$ROOT_DIR/scripts/install.sh" >/dev/null 2>&1
)

# Non-dry-run marker write (covers the date > "$MARKER_FILE" line).
(
  RETRO_HA_ALLOW_NON_ROOT=1 RETRO_HA_DRY_RUN=0 KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=ok \
    PATH="$stub_bin:/usr/bin:/bin" bash "$ROOT_DIR/scripts/install.sh" >/dev/null 2>&1
)

# Require-root failure branch.
(
  set +e
  RETRO_HA_ALLOW_NON_ROOT=0 KCOV_RETROPI_EXISTS=1 KCOV_APT_CACHE_MODE=none KCOV_FLOCK_MODE=ok \
    PATH="$stub_bin:/usr/bin:/bin" bash "$ROOT_DIR/scripts/install.sh" >/dev/null 2>&1
) || true
