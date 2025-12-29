#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== tests-path-coverage: required PATH ids =="
"$repo_root/tests/bin/recalc-path-coverage.sh" --no-run
