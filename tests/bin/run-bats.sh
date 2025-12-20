#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# This is the "run everything" entrypoint used by `make test`.
# It intentionally preserves the split between unit and integration suites:
# - unit suite enforces only lib-* path IDs
# - integration suite enforces all non-lib path IDs

# Disallow selecting individual files here; use the suite runners for that.
for arg in "$@"; do
  if [[ "$arg" == *.bats ]]; then
    echo "run-bats.sh does not accept explicit .bats files." >&2
    echo "Use: $ROOT_DIR/tests/bin/run-bats-unit.sh <file.bats> or run-bats-integration.sh <file.bats>" >&2
    exit 2
  fi
done

"$ROOT_DIR/tests/bin/run-bats-unit.sh" "$@"
"$ROOT_DIR/tests/bin/run-bats-integration.sh" "$@"

echo
"$ROOT_DIR/tests/bin/recalc-path-coverage.sh" --no-run
