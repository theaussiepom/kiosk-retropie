#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== coverage: kcov =="
ci_require_cmd kcov
ci_require_cmd strace

# Write kcov output to a temp folder by default.
# This avoids deleting the committed ./coverage directory when running locally.
# Use a unique directory per run to avoid flakiness on network filesystems
# (e.g., transient "Directory not empty" errors when deleting a previous run).
if [[ -z "${KCOV_OUT_DIR:-}" ]]; then
  mkdir -p "$repo_root/tests/.tmp" 2> /dev/null || true
  KCOV_OUT_DIR="$(mktemp -d "$repo_root/tests/.tmp/kcov.XXXXXX")"
fi
export KCOV_OUT_DIR

KCOV_ALLOW_NONZERO_WITH_REPORT=1 "$repo_root/tests/bin/run-bats-kcov.sh"
"$repo_root/tests/bin/assert-kcov-100.sh"
