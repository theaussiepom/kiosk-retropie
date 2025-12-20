#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tests/bin/recalc-path-coverage.sh [--run|--no-run]
                                     [--required-file <path>]
                                     [--unit-log <path>]
                                     [--integration-log <path>]

Prints path-coverage counts derived from:
  - tests/coverage/required-paths.txt
  - tests/.tmp/retro-ha-paths.unit.log
  - tests/.tmp/retro-ha-paths.log

IDs are partitioned by convention:
  - unit owns IDs that start with "lib-"
  - integration owns all other required IDs

Output keys:
  required_ids_total
  required_ids_unit
  required_ids_integration
  unit_uncovered_required_ids
  integration_uncovered_required_ids
  union_uncovered_required_ids

Exit codes:
  0 on success
  2 on usage error
  3 if a required file/log file is missing (with --no-run)
EOF
}

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

do_run=0
required_file="$repo_root/tests/coverage/required-paths.txt"
unit_log="$repo_root/tests/.tmp/retro-ha-paths.unit.log"
integration_log="$repo_root/tests/.tmp/retro-ha-paths.log"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --run)
      do_run=1
      shift
      ;;
    --no-run)
      do_run=0
      shift
      ;;
    --required-file)
      required_file="${2:-}"
      shift 2
      ;;
    --unit-log)
      unit_log="${2:-}"
      shift 2
      ;;
    --integration-log)
      integration_log="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$do_run" == "1" ]]; then
  "$repo_root/tests/bin/run-bats-unit.sh" >/dev/null
  "$repo_root/tests/bin/run-bats-integration.sh" >/dev/null
fi

if [[ ! -f "$required_file" ]]; then
  echo "Missing required file: $required_file" >&2
  exit 3
fi

if [[ ! -f "$unit_log" ]]; then
  echo "Missing unit paths log: $unit_log" >&2
  echo "Hint: run: $repo_root/tests/bin/run-bats-unit.sh (or pass --run)" >&2
  exit 3
fi

if [[ ! -f "$integration_log" ]]; then
  echo "Missing integration paths log: $integration_log" >&2
  echo "Hint: run: $repo_root/tests/bin/run-bats-integration.sh (or pass --run)" >&2
  exit 3
fi

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir" || true; }
trap cleanup EXIT

required_all="$tmpdir/required.all"
required_unit="$tmpdir/required.unit"
required_integration="$tmpdir/required.integration"

covered_unit="$tmpdir/covered.unit"
covered_integration="$tmpdir/covered.integration"
covered_union="$tmpdir/covered.union"

grep -vE '^(#|[[:space:]]*$)' "$required_file" | sort -u >"$required_all"
grep -E '^lib-' "$required_all" | sort -u >"$required_unit" || true
grep -vE '^lib-' "$required_all" | sort -u >"$required_integration" || true

grep -oP '^PATH \K.*' "$unit_log" | sort -u >"$covered_unit" || true
grep -oP '^PATH \K.*' "$integration_log" | sort -u >"$covered_integration" || true
cat "$covered_unit" "$covered_integration" | sort -u >"$covered_union" || true

required_ids_total="$(wc -l <"$required_all" | tr -d '[:space:]')"
required_ids_unit="$(wc -l <"$required_unit" | tr -d '[:space:]')"
required_ids_integration="$(wc -l <"$required_integration" | tr -d '[:space:]')"

unit_misses="$(comm -23 "$required_unit" "$covered_unit" | wc -l | tr -d '[:space:]')"
integration_misses="$(comm -23 "$required_integration" "$covered_integration" | wc -l | tr -d '[:space:]')"
union_misses="$(comm -23 "$required_all" "$covered_union" | wc -l | tr -d '[:space:]')"

echo "required_ids_total=$required_ids_total"
echo "required_ids_unit=$required_ids_unit"
echo "required_ids_integration=$required_ids_integration"
echo "unit_uncovered_required_ids=$unit_misses"
echo "integration_uncovered_required_ids=$integration_misses"
echo "union_uncovered_required_ids=$union_misses"
