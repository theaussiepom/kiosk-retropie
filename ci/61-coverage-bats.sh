#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== coverage-bats: kcov bats =="
ci_require_cmd kcov
ci_require_cmd strace

suite="${KCOV_BATS_SUITE:-integration}"
runner=""
case "$suite" in
  unit) runner="$repo_root/tests/bin/run-bats-unit.sh" ;;
  integration) runner="$repo_root/tests/bin/run-bats-integration.sh" ;;
  *)
    echo "Invalid KCOV_BATS_SUITE value: $suite" >&2
    echo "Allowed: unit | integration" >&2
    exit 2
    ;;
esac

echo "== coverage-bats: bats (no kcov) [$suite] =="
original_kcov_out_dir="${KCOV_OUT_DIR:-}"
unset KCOV_OUT_DIR
"$runner"

if [[ -n "$original_kcov_out_dir" ]]; then
  export KCOV_OUT_DIR="$original_kcov_out_dir"
fi

# Write kcov output to a temp folder by default.
# Use a unique directory per run to avoid flakiness on network filesystems.
if [[ -z "${KCOV_OUT_DIR:-}" ]]; then
  mkdir -p "$repo_root/tests/.tmp" 2> /dev/null || true
  KCOV_OUT_DIR="$(mktemp -d "$repo_root/tests/.tmp/kcov-bats.XXXXXX")"
fi
export KCOV_OUT_DIR

KCOV_STEPS=bats KCOV_BATS_SUITE="$suite" KCOV_ALLOW_NONZERO_WITH_REPORT=1 "$repo_root/tests/bin/run-bats-kcov.sh"
