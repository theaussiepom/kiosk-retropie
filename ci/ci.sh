#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

run_part() {
  local path="$repo_root/ci/$1"
  if [[ ! -x "$path" ]]; then
    echo "CI part missing or not executable: $path" >&2
    return 1
  fi
  "$path"
}

# Default pipeline: lint + systemd + coverage.
# Note: coverage runs the Bats suite under kcov, so running the plain tests stage
# as part of the default pipeline would duplicate work.
parts=(05-lint-permissions.sh 06-lint-naming.sh 10-lint-sh.sh 30-lint-yaml.sh 40-lint-systemd.sh 50-lint-markdown.sh 60-coverage.sh)

if [[ $# -gt 0 ]]; then
  parts=()
  for p in "$@"; do
    case "$p" in
      lint-sh) parts+=(10-lint-sh.sh) ;;
      lint-naming) parts+=(06-lint-naming.sh) ;;
      lint-yaml) parts+=(30-lint-yaml.sh) ;;
      lint-systemd) parts+=(40-lint-systemd.sh) ;;
      lint-markdown) parts+=(50-lint-markdown.sh) ;;
      tests) parts+=(20-tests.sh) ;;
      coverage) parts+=(60-coverage.sh) ;;
      lint-permissions) parts+=(05-lint-permissions.sh) ;;
      *)
        echo "Unknown CI part: $p" >&2
        echo "Valid parts: lint-permissions lint-naming lint-sh lint-yaml lint-systemd lint-markdown tests coverage" >&2
        exit 2
        ;;
    esac
  done
fi

part=""
for part in "${parts[@]}"; do
  run_part "$part"
done

echo "== done =="
