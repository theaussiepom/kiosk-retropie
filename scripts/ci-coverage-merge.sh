#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
merge_input="$repo_root/tests/.tmp/kcov-merge-input"

if [[ ! -d "$merge_input" ]]; then
  echo "KCOV merge input dir does not exist: $merge_input" >&2
  exit 1
fi

bats_unit_dir="$(
  find "$merge_input/bats-unit" -maxdepth 8 -type f -name index.html -print0 -quit |
    xargs -0 -r dirname
)"
if [[ -z "$bats_unit_dir" ]]; then
  echo "Could not locate bats unit kcov output under: $merge_input/bats-unit" >&2
  find "$merge_input/bats-unit" -maxdepth 4 -print >&2 || true
  exit 1
fi

bats_integration_dir="$(
  find "$merge_input/bats-integration" -maxdepth 8 -type f -name index.html -print0 -quit |
    xargs -0 -r dirname
)"
if [[ -z "$bats_integration_dir" ]]; then
  echo "Could not locate bats integration kcov output under: $merge_input/bats-integration" >&2
  find "$merge_input/bats-integration" -maxdepth 4 -print >&2 || true
  exit 1
fi

wrapped_dir="$(
  find "$merge_input" -maxdepth 10 -type d -path "*/coverage-wrapped/kcov-merged" -print -quit
)"
if [[ -z "$wrapped_dir" ]]; then
  echo "Could not locate scripts wrapped merge dir under: $merge_input" >&2
  find "$merge_input" -maxdepth 4 -print >&2 || true
  exit 1
fi

# kcov writes coverage.json under a per-command subdirectory, not directly under the
# coverage output directory. Locate the kcov-line-coverage output robustly.
scripts_coverage_leaf_dir="$(
  find "$merge_input" -maxdepth 10 -type f -name coverage.json \
    -path "*/kcov-line-coverage.sh.*/*" \
    -not -path "*/coverage-wrapped/*" \
    -print0 -quit |
    xargs -0 -r dirname
)"
if [[ -z "$scripts_coverage_leaf_dir" ]]; then
  echo "Could not locate scripts kcov-line coverage.json under: $merge_input" >&2
  find "$merge_input" -maxdepth 4 -print >&2 || true
  exit 1
fi

scripts_coverage_dir="$(dirname "$scripts_coverage_leaf_dir")"
if [[ ! -f "$scripts_coverage_dir/index.html" ]]; then
  echo "Could not locate scripts kcov-line index.html at: $scripts_coverage_dir/index.html" >&2
  find "$scripts_coverage_dir" -maxdepth 2 -print >&2 || true
  exit 1
fi

export KCOV_OUT_DIR="$repo_root/tests/.tmp/kcov-merge-out"
export KCOV_MERGE_BATS_DIRS
KCOV_MERGE_BATS_DIRS="$(printf "%s,%s" "$bats_unit_dir" "$bats_integration_dir")"
export KCOV_MERGE_COVERAGE_DIR="$scripts_coverage_dir"
export KCOV_MERGE_WRAPPED_DIR="$wrapped_dir"

"$repo_root/scripts/ci.sh" coverage-merge
