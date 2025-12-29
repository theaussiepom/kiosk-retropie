#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== coverage-merge: kcov merge + assert =="
ci_require_cmd kcov
ci_require_cmd strace

if [[ -z "${KCOV_OUT_DIR:-}" ]]; then
  mkdir -p "$repo_root/tests/.tmp" 2> /dev/null || true
  KCOV_OUT_DIR="$(mktemp -d "$repo_root/tests/.tmp/kcov-merge.XXXXXX")"
fi
export KCOV_OUT_DIR

# Inputs can be provided via KCOV_MERGE_* env vars.
KCOV_STEPS=merge "$repo_root/tests/bin/run-bats-kcov.sh"

"$repo_root/tests/bin/assert-kcov-100.sh"
