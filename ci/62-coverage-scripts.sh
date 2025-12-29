#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== coverage-scripts: kcov scripts =="
ci_require_cmd kcov
ci_require_cmd strace

# Write kcov output to a temp folder by default.
# Use a unique directory per run to avoid flakiness on network filesystems.
if [[ -z "${KCOV_OUT_DIR:-}" ]]; then
  mkdir -p "$repo_root/tests/.tmp" 2> /dev/null || true
  KCOV_OUT_DIR="$(mktemp -d "$repo_root/tests/.tmp/kcov-scripts.XXXXXX")"
fi
export KCOV_OUT_DIR

KCOV_STEPS=coverage "$repo_root/tests/bin/run-bats-kcov.sh"
