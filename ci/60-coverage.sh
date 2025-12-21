#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== coverage: kcov =="
ci_require_cmd kcov
ci_require_cmd strace

KCOV_ALLOW_NONZERO_WITH_REPORT=1 "$repo_root/tests/bin/run-bats-kcov.sh"
"$repo_root/tests/bin/assert-kcov-100.sh"
