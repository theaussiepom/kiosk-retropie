#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== lint-permissions: executable bits =="

# We rely on git to carry executable bits across environments (especially CI).
# If these drift, GitHub Actions checkouts may lose +x and coverage wrapping breaks.

fail=0

check_tree() {
  local prefix="$1"

  # Only consider tracked files to avoid false positives from local build artifacts.
  mapfile -t files < <(git ls-files "$prefix" | grep -E '\.sh$' || true)

  local f
  for f in "${files[@]}"; do
    if [[ ! -x "$f" ]]; then
      echo "lint-permissions [error]: not executable (expected +x): $f" >&2
      fail=1
    fi
  done
}

check_tree "ci"
check_tree "scripts"
check_tree "tests/bin"

if [[ "$fail" -ne 0 ]]; then
  echo "lint-permissions [hint]: fix with: git update-index --chmod=+x <file>" >&2
  exit 1
fi
