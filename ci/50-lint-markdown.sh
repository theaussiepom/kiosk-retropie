#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== lint-markdown: markdownlint =="
ci_require_cmd markdownlint

mapfile -d '' md_files < <(ci_list_markdown_files || true)
if [[ ${#md_files[@]} -eq 0 ]]; then
  echo "No markdown files found, skipping."
  exit 0
fi

markdownlint -c .markdownlint.json "${md_files[@]}"
