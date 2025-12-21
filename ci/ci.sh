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

parts=(10-shell.sh 30-yaml.sh 40-systemd.sh 50-markdown.sh 20-tests.sh 60-coverage.sh)

if [[ $# -gt 0 ]]; then
  parts=()
  for p in "$@"; do
    case "$p" in
      shell) parts+=(10-shell.sh) ;;
      yaml) parts+=(30-yaml.sh) ;;
      systemd) parts+=(40-systemd.sh) ;;
      markdown) parts+=(50-markdown.sh) ;;
      tests) parts+=(20-tests.sh) ;;
      coverage) parts+=(60-coverage.sh) ;;
      *)
        echo "Unknown CI part: $p" >&2
        echo "Valid parts: shell yaml systemd markdown tests coverage" >&2
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
