#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== lint-sh: bash -n =="
mapfile -d '' shell_files < <(ci_list_shell_files || true)
if [[ ${#shell_files[@]} -eq 0 ]]; then
  echo "No shell scripts found under scripts/ or ci/, skipping."
else
  local_f=""
  for local_f in "${shell_files[@]}"; do
    echo "bash -n $local_f"
    bash -n "$local_f"
  done
fi

echo "== lint-sh: shellcheck =="
ci_require_cmd shellcheck
if [[ ${#shell_files[@]} -eq 0 ]]; then
  echo "No shell scripts found under scripts/ or ci/, skipping."
else
  shellcheck "${shell_files[@]}"
fi

echo "== lint-sh: shfmt =="
ci_require_cmd shfmt
if [[ ${#shell_files[@]} -eq 0 ]]; then
  echo "No shell scripts found under scripts/ or ci/, skipping."
else
  shfmt -d -i 2 -ci -sr "${shell_files[@]}"
fi
