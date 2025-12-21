#!/usr/bin/env bash
set -euo pipefail

# Shared helpers for CI scripts.

ci_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

ci_cd_repo_root() {
  local root
  root="$(ci_repo_root)"
  cd "$root"
}

ci_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    return 1
  fi
}

# Print NUL-delimited list of files under the given roots matching the find expression.
ci_find0() {
  # Usage: ci_find0 <root>... -- <find expr...>
  local roots=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      break
    fi
    roots+=("$1")
    shift
  done

  if [[ ${#roots[@]} -eq 0 ]]; then
    return 0
  fi

  local r
  for r in "${roots[@]}"; do
    [[ -d "$r" ]] || continue
    find "$r" \
      -type d \( -name .git -o -name node_modules -o -name coverage -o -name 'coverage-*' -o -name tests/vendor \) -prune -o \
      "${@}" -print0
  done
}

ci_list_shell_files() {
  ci_find0 scripts ci -- -type f -name '*.sh'
}

ci_list_yaml_files() {
  ci_find0 .github cloud-init examples -- -type f \( -name '*.yml' -o -name '*.yaml' \)
}

ci_list_unit_files() {
  ci_find0 systemd -- -type f \( \
    -name '*.service' -o -name '*.timer' -o -name '*.target' -o -name '*.path' -o -name '*.socket' -o -name '*.mount' \
    \)
}

ci_list_service_files() {
  ci_find0 systemd -- -type f -name '*.service'
}

ci_list_markdown_files() {
  local f
  for f in README.md CHANGELOG.md CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md; do
    if [[ -f "$f" ]]; then
      printf '%s\0' "$f"
    fi
  done

  ci_find0 docs -- -type f -name '*.md'
}
