#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== lint-yaml: yamllint =="
ci_require_cmd yamllint

mapfile -d '' yaml_files < <(ci_list_yaml_files || true)
if [[ ${#yaml_files[@]} -eq 0 ]]; then
  echo "No YAML files found in expected locations, skipping."
  exit 0
fi

yamllint -c .yamllint.yml "${yaml_files[@]}"
