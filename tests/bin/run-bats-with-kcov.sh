#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# Run the integration suite (we already run it in CI with full output).
"$ROOT_DIR/tests/bin/run-bats-integration.sh" >/dev/null

# Run extra coverage exercises (coverage) to improve kcov line coverage.
"$ROOT_DIR/tests/bin/kcov-line-coverage.sh" >/dev/null
