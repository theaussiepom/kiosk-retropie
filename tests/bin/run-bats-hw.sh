#!/usr/bin/env bash
set -euo pipefail

# Dedicated “hardware-ish” functional tests.
# These are intended to run on the self-hosted Raspberry Pi runner.

# Ensure a sane PATH even if the calling shell mutated it.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# Stable repo-root path for tests (avoids depending on $BATS_TEST_DIRNAME-relative paths).
export KIOSK_RETROPIE_REPO_ROOT="$ROOT_DIR"

"$ROOT_DIR/tests/bin/fetch-bats.sh" >/dev/null

# Allow `load 'vendor/...'` and `load 'helpers/...'` from nested test folders.
export BATS_LOAD_PATH="$ROOT_DIR/tests:$ROOT_DIR/tests/vendor"
export BATS_LIB_PATH="$ROOT_DIR/tests/vendor:$ROOT_DIR/tests"

# Stable path-coverage log shared across Bats invocations.
PATHS_LOG="${KIOSK_RETROPIE_PATHS_FILE:-$ROOT_DIR/tests/.tmp/kiosk-retropie-paths.hw.log}"
mkdir -p "$(dirname "$PATHS_LOG")"
rm -f "$PATHS_LOG"
export KIOSK_RETROPIE_PATHS_FILE="$PATHS_LOG"
export KIOSK_RETROPIE_PATH_COVERAGE=1

shopt -s nullglob

test_files=(
  "$ROOT_DIR/tests/hw"/*.bats
)

shopt -u nullglob

if [[ "${#test_files[@]}" -eq 0 ]]; then
  echo "No hardware tests found under tests/hw/" >&2
  exit 0
fi

exec "$ROOT_DIR/tests/vendor/bats-core/bin/bats" "${test_files[@]}" "$@"
