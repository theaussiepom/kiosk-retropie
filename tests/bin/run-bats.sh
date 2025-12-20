#!/usr/bin/env bash
set -euo pipefail

# Ensure a sane PATH even if the calling shell mutated it.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# Stable repo-root path for tests (avoids depending on $BATS_TEST_DIRNAME-relative paths).
export RETRO_HA_REPO_ROOT="$ROOT_DIR"

"$ROOT_DIR/tests/bin/fetch-bats.sh" >/dev/null

# Allow `load 'vendor/...'` and `load 'helpers/...'` from nested test folders.
export BATS_LOAD_PATH="$ROOT_DIR/tests:$ROOT_DIR/tests/vendor"
export BATS_LIB_PATH="$ROOT_DIR/tests/vendor:$ROOT_DIR/tests"

# Stable path-coverage log shared across Bats invocations.
PATHS_LOG="${RETRO_HA_PATHS_FILE:-$ROOT_DIR/tests/.tmp/retro-ha-paths.log}"
mkdir -p "$(dirname "$PATHS_LOG")"
rm -f "$PATHS_LOG"
export RETRO_HA_PATHS_FILE="$PATHS_LOG"

shopt -s nullglob
test_files=(
	"$ROOT_DIR/tests/unit"/*.bats
	"$ROOT_DIR/tests/integration"/*.bats
)

# Always run the suite-level path coverage check last.
path_coverage_file="$ROOT_DIR/tests/unit/zz-path-coverage.bats"
if [[ -f "$path_coverage_file" ]]; then
	filtered=()
	for f in "${test_files[@]}"; do
		if [[ "$f" != "$path_coverage_file" ]]; then
			filtered+=("$f")
		fi
	done
	test_files=("${filtered[@]}" "$path_coverage_file")
fi

shopt -u nullglob
exec "$ROOT_DIR/tests/vendor/bats-core/bin/bats" "${test_files[@]}" "$@"
