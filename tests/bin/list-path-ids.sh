#!/usr/bin/env bash
set -euo pipefail

# Emit all path coverage IDs that exist in production scripts.
# This is used to ensure tests/coverage/required-paths.txt stays complete.

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# 1) Bash: cover_path "id"
# 2) Bash: retro_ha__cover_path_raw "id"
# 3) Python (embedded): cover_path("id")
#    (We intentionally keep this simple: only literal string IDs.)

{
  grep -R --binary-files=without-match --line-number --exclude-dir=.tmp --exclude-dir=vendor \
    -E 'cover_path "|retro_ha__cover_path_raw "' "$repo_root/scripts" \
    | sed -n 's/.*\(cover_path\|retro_ha__cover_path_raw\) "\([^"]*\)".*/\2/p'

  grep -R --binary-files=without-match --line-number --exclude-dir=.tmp --exclude-dir=vendor \
    -E 'cover_path\("' "$repo_root/scripts" \
    | sed -n 's/.*cover_path("\([^"]*\)".*/\1/p'
} \
  | grep -E '^[A-Za-z0-9][A-Za-z0-9:_-]*$' \
  | sort -u
