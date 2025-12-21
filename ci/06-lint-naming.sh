#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== lint-naming: conventions =="

fail=0

echo "== lint-naming: filenames =="

# Repo-wide filename conventions:
# - Prefer lowercase + digits + '.' + '-' (no underscores)
# - Allow a small set of conventional GitHub/repo names
declare -A allowed_basenames=()
allowed_basenames[README.md]=1
allowed_basenames[CHANGELOG.md]=1
allowed_basenames[CODE_OF_CONDUCT.md]=1
allowed_basenames[CONTRIBUTING.md]=1
allowed_basenames[LICENSE]=1
allowed_basenames[SECURITY.md]=1
allowed_basenames[Makefile]=1
allowed_basenames[Dockerfile]=1
allowed_basenames[PULL_REQUEST_TEMPLATE.md]=1
allowed_basenames[mosquitto_pub]=1
allowed_basenames[mosquitto_sub]=1

mapfile -t tracked_files < <(git ls-files | sort)
for f in "${tracked_files[@]}"; do
  base="${f##*/}"

  if [[ -n "${allowed_basenames[$base]:-}" ]]; then
    continue
  fi

  if [[ "$base" == .* ]]; then
    # Hidden files (e.g. .gitignore). None are tracked today, but allow.
    continue
  fi

  # Kebab-case per dot-separated segment (e.g. user-data.example.yml).
  # No underscores or capitals.
  if ! [[ "$base" =~ ^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+(-[a-z0-9]+)*)*$ ]]; then
    echo "lint-naming [error]: filename must be kebab-case (dot-separated segments allowed) or in allowlist: $f" >&2
    fail=1
  fi
done

echo "== lint-naming: ci stage scripts =="

# Enforce predictable naming for CI stage scripts.
# - `ci/NN-name.sh` where NN is 2 digits
# - kebab-case stage name
# - no legacy `shell` naming (use `lint-sh`)
mapfile -t ci_files < <(git ls-files "ci" | sort)

declare -A seen_stage_nums=()

for f in "${ci_files[@]}"; do
  base="${f##*/}"
  case "$base" in
    ci.sh | lib.sh)
      continue
      ;;
  esac

  if [[ "$base" != *.sh ]]; then
    echo "lint-naming [error]: ci file must end with .sh: $f" >&2
    fail=1
    continue
  fi

  if [[ "$base" == *shell* ]]; then
    echo "lint-naming [error]: legacy name contains 'shell' (use 'lint-sh'): $f" >&2
    fail=1
  fi

  if ! [[ "$base" =~ ^[0-9]{2}-[a-z0-9]+([a-z0-9-]*[a-z0-9])?\.sh$ ]]; then
    echo "lint-naming [error]: ci stage must be named ci/NN-kebab-case.sh: $f" >&2
    fail=1
    continue
  fi

  stage_num="${base:0:2}"
  if [[ -n "${seen_stage_nums[$stage_num]:-}" ]]; then
    echo "lint-naming [error]: duplicate ci stage number $stage_num: $f" >&2
    fail=1
  else
    seen_stage_nums[$stage_num]=1
  fi

done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
