#!/usr/bin/env bash
set -euo pipefail

# Ensure a sane PATH even if the calling shell mutated it.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# Stable repo-root path for tests (avoids depending on $BATS_TEST_DIRNAME-relative paths).
export KIOSK_RETROPIE_REPO_ROOT="$ROOT_DIR"

"$ROOT_DIR/tests/bin/fetch-bats.sh" >/dev/null

export BATS_LOAD_PATH="$ROOT_DIR/tests:$ROOT_DIR/tests/vendor"
export BATS_LIB_PATH="$ROOT_DIR/tests/vendor:$ROOT_DIR/tests"

if ! command -v kcov >/dev/null 2>&1; then
  echo "kcov not found on PATH" >&2
  exit 127
fi

kcov_steps="${KCOV_STEPS:-all}"

step_enabled() {
  local want="$1"
  if [[ "$kcov_steps" == "all" ]]; then
    return 0
  fi
  local IFS=','
  # shellcheck disable=SC2206 # intentional word-splitting on comma-separated list
  local parts=($kcov_steps)
  local p
  for p in "${parts[@]}"; do
    if [[ "$p" == "$want" ]]; then
      return 0
    fi
  done
  return 1
}

if [[ "$kcov_steps" != "all" ]]; then
  for required in bats coverage merge; do
    if step_enabled "$required"; then
      continue
    fi
  done
  # Validate user input: every token must be one of the allowed steps.
  IFS=',' read -r -a _kcov_steps_parts <<<"$kcov_steps"
  for part in "${_kcov_steps_parts[@]}"; do
    case "$part" in
      bats|coverage|merge) ;;
      *)
        echo "Invalid KCOV_STEPS value: $kcov_steps (bad token: $part)" >&2
        echo "Allowed: all | bats | coverage | merge | bats,coverage | bats,coverage,merge" >&2
        exit 2
        ;;
    esac
  done
  unset -v _kcov_steps_parts
fi

out_dir="${KCOV_OUT_DIR:-$ROOT_DIR/coverage}"

# For full runs (bats/coverage), start from a clean output directory.
# For merge-only runs, allow using a pre-existing directory (or separate inputs
# via KCOV_MERGE_* env vars) without wiping it.
if step_enabled bats || step_enabled coverage; then
  rm -rf "$out_dir"
fi
mkdir -p "$out_dir"

# Run the Bats suite under kcov to gather coverage for scripts/**.
# Prefer the explicit bash parser flag; older kcov versions use different names.
# Exclude tests and vendored bats libs.

# Some kcov builds (including Ubuntu packages) hide bash-specific options
# behind --uncommon-options.
kcov_help="$(kcov --help --uncommon-options 2>&1 || kcov --help 2>&1 || true)"
bash_parser_flag=""
bash_method_flag=""
report_type_args=()
kcov_arg_order="${KCOV_ARG_ORDER:-opts_first}"
if grep -Fq -- '--bash-parser=cmd' <<<"$kcov_help"; then
  bash_parser_flag="--bash-parser=/bin/bash"
elif grep -Fq -- '--bash-parser' <<<"$kcov_help"; then
  bash_parser_flag="--bash-parser=/bin/bash"
fi

if grep -Fq -- '--bash-method=method' <<<"$kcov_help"; then
  bash_method="${KCOV_BASH_METHOD:-DEBUG}"
  bash_method_flag="--bash-method=${bash_method}"
fi

# Some kcov versions only emit coverage.json when JSON reporting is explicitly enabled.
if grep -Fq -- '--report-type' <<<"$kcov_help"; then
  report_type_args+=(--report-type=html --report-type=json)
fi

echo "kcov version: $(kcov --version 2>/dev/null || echo unknown)" >&2
echo "kcov path: $(command -v kcov)" >&2
echo "kcov capabilities (grep):" >&2
grep -E '(^|\s)--(bash|report-type|verbose|debug|merge)' <<<"$kcov_help" >&2 || true

usage_line="$(grep -E '^Usage:' <<<"$kcov_help" | head -n 1 || true)"
if [[ -n "$usage_line" ]]; then
  echo "$usage_line" >&2
fi
echo "kcov arg order: $kcov_arg_order" >&2

common_args=()
if [[ -n "$bash_parser_flag" ]]; then
  common_args+=("$bash_parser_flag")
fi
if [[ -n "$bash_method_flag" ]]; then
  common_args+=("$bash_method_flag")
fi
common_args+=(
  "${report_type_args[@]}"
  --include-path="$ROOT_DIR/scripts"
  --exclude-pattern="$ROOT_DIR/tests,$ROOT_DIR/tests/vendor,$ROOT_DIR/scripts/ci.sh"
)

run_kcov() {
  local label="$1"
  local display_label="$2"
  local out="$3"
  local cmd="$4"
  shift 4

  local log_file="$out_dir/${label}.log"
  local strace_file="$out_dir/${label}.strace"
  local timeout_bin=""
  local timeout_seconds="${KCOV_TIMEOUT_SECONDS:-600}"

  build_kcov_cmd() {
    local order="$1"
    shift
    local -a built=(kcov)
    if [[ "$order" == "out_first" ]]; then
      built+=("$out" "${common_args[@]}" "$cmd" "$@")
    else
      built+=("${common_args[@]}" "$out" "$cmd" "$@")
    fi
    printf '%s\n' "${built[@]}"
  }

  # Use a single, explicit argument order. (No fallback/retry.)
  local -a kcov_cmd
  mapfile -t kcov_cmd < <(build_kcov_cmd "$kcov_arg_order")

  echo "kcov step: $display_label" >&2
  echo "+ ${kcov_cmd[*]}" >&2

  if command -v timeout >/dev/null 2>&1; then
    timeout_bin="timeout"
  fi

  # Capture stdout+stderr to a log file so we can print it on failure.
  run_one() {
    local -n _cmd_ref=$1
    local _out_log="$2"
    if [[ -n "$timeout_bin" ]]; then
      "$timeout_bin" --foreground -k 10s "${timeout_seconds}s" "${_cmd_ref[@]}" >"$_out_log" 2>&1
      return $?
    fi
    "${_cmd_ref[@]}" >"$_out_log" 2>&1
    return $?
  }

  local rc=0
  if run_one kcov_cmd "$log_file"; then
    return 0
  else
    rc=$?
  fi

  # In CI we run Bats once without kcov (for correctness) and a second time under
  # kcov (for coverage). Some kcov/bats combinations can return non-zero while
  # still producing a valid coverage report. When enabled, treat that as success
  # so we can proceed to coverage+merge and still enforce coverage.
  if [[ "${KCOV_ALLOW_NONZERO_WITH_REPORT:-0}" == "1" && "$rc" -ne 0 ]]; then
    if find "$out" -maxdepth 4 -name coverage.json -print -quit 2>/dev/null | grep -q .; then
      echo "kcov step returned non-zero but produced coverage.json; continuing: $display_label (exit=$rc)" >&2
      return 0
    fi
  fi

  if [[ "$rc" -eq 124 ]]; then
    echo "kcov step timed out after ${timeout_seconds}s: $display_label" >&2
  fi

  # If kcov failed and produced no output, capture a small strace to help debug
  # CI-only failures. Keep it narrow to avoid massive artifacts.
  if [[ "$rc" -ne 0 && ( ! -s "$log_file" || "$(wc -c <"$log_file" 2>/dev/null || echo 0)" -lt 200 ) ]]; then
    if command -v strace >/dev/null 2>&1; then
      echo "kcov produced little/no output; capturing strace to $strace_file" >&2
      # Trace process/exec/file plus writes to stderr; enough to spot missing binaries,
      # permissions, and any errors kcov/subprocess writes.
      if [[ -n "$timeout_bin" ]]; then
        "$timeout_bin" --foreground -k 5s 60s strace -f -qq -s 200 -o "$strace_file" -e trace=process,execve,file,write -e write=2 "${kcov_cmd[@]}" >/dev/null 2>&1 || true
      else
        strace -f -qq -s 200 -o "$strace_file" -e trace=process,execve,file,write -e write=2 "${kcov_cmd[@]}" >/dev/null 2>&1 || true
      fi
    fi
  fi

  # If we ever reach here with rc==0, treat that as success.
  if [[ "$rc" -eq 0 ]]; then
    return 0
  fi

  echo "kcov step failed: $label (exit=$rc)" >&2
  echo "--- $log_file (last 200 lines) ---" >&2
  tail -n 200 "$log_file" >&2 || true
  if [[ -f "$strace_file" ]]; then
    echo "--- $strace_file (last 200 lines) ---" >&2
    tail -n 200 "$strace_file" >&2 || true

    echo "--- $strace_file (execve failures) ---" >&2
    grep -E 'execve\(.*\) = -1 ' "$strace_file" | tail -n 50 >&2 || true
  fi
  exit "$rc"
}

run_kcov_merge() {
  local label="$1"
  local out="$2"
  shift 2

  local log_file="$out_dir/${label}.log"
  local strace_file="$out_dir/${label}.strace"
  local timeout_bin=""
  local timeout_seconds="${KCOV_TIMEOUT_SECONDS:-600}"

  local -a kcov_cmd=(kcov --merge "$out" "$@")

  echo "kcov step: $label" >&2
  echo "+ ${kcov_cmd[*]}" >&2

  if command -v timeout >/dev/null 2>&1; then
    timeout_bin="timeout"
  fi

  local rc=0
  if [[ -n "$timeout_bin" ]]; then
    if "$timeout_bin" --foreground -k 10s "${timeout_seconds}s" "${kcov_cmd[@]}" >"$log_file" 2>&1; then
      return 0
    fi
    rc=$?
  else
    if "${kcov_cmd[@]}" >"$log_file" 2>&1; then
      return 0
    fi
    rc=$?
  fi

  if [[ "$rc" -eq 124 ]]; then
    echo "kcov step timed out after ${timeout_seconds}s: $label" >&2
  fi

  if [[ ! -s "$log_file" ]] || [[ "$(wc -c <"$log_file" 2>/dev/null || echo 0)" -lt 200 ]]; then
    if command -v strace >/dev/null 2>&1; then
      echo "kcov produced little/no output; capturing strace to $strace_file" >&2
      if [[ -n "$timeout_bin" ]]; then
        "$timeout_bin" --foreground -k 5s 60s strace -f -qq -s 200 -o "$strace_file" -e trace=process,execve,file,write -e write=2 "${kcov_cmd[@]}" >/dev/null 2>&1 || true
      else
        strace -f -qq -s 200 -o "$strace_file" -e trace=process,execve,file,write -e write=2 "${kcov_cmd[@]}" >/dev/null 2>&1 || true
      fi
    fi
  fi

  echo "kcov step failed: $display_label (exit=$rc)" >&2
  echo "--- $log_file (last 200 lines) ---" >&2
  tail -n 200 "$log_file" >&2 || true
  if [[ -f "$strace_file" ]]; then
    echo "--- $strace_file (execve failures) ---" >&2
    grep -E 'execve\(.*\) = -1 ' "$strace_file" | tail -n 50 >&2 || true
  fi
  exit "$rc"
}


# kcov bash coverage can behave differently depending on whether the traced
# process exec()s into bats. To keep the original behavior (which already
# captured coverage from the Bats suite), run Bats under kcov as its own run.
if step_enabled bats; then
  bats_suite="${KCOV_BATS_SUITE:-integration}"
  bats_runner=""
  case "$bats_suite" in
    unit) bats_runner="$ROOT_DIR/tests/bin/run-bats-unit.sh" ;;
    integration) bats_runner="$ROOT_DIR/tests/bin/run-bats-integration.sh" ;;
    *)
      echo "Invalid KCOV_BATS_SUITE value: $bats_suite" >&2
      echo "Allowed: unit | integration" >&2
      exit 2
      ;;
  esac

  run_kcov "bats" "Bash Automated Testing System (bats) [$bats_suite]" "$out_dir/bats" "$bats_runner" "$@"
fi

# Run additional coverage paths under kcov.
#
# NOTE: kcov bash coverage does not reliably attribute coverage to scripts
# executed as separate bash processes in some environments (notably containers).
# The coverage run therefore also self-wraps each invoked script in its own kcov run
# (written to $out_dir/coverage-wrapped) and merges those results.
if step_enabled coverage; then
  mkdir -p "$out_dir/coverage-wrapped"

  # IMPORTANT: These need to be exported so they are visible to the kcov-run process
  # (and therefore to kcov-line-coverage.sh itself).
  export KCOV_WRAP=1
  export KCOV_WRAP_OUT_DIR="$out_dir/coverage-wrapped"
  run_kcov "coverage" "coverage" "$out_dir/coverage" "$ROOT_DIR/tests/bin/kcov-line-coverage.sh"
  unset -v KCOV_WRAP KCOV_WRAP_OUT_DIR
fi

# Merge into a stable location consumed by assert-kcov-100.sh.
if step_enabled merge; then
  merge_bats_dir="${KCOV_MERGE_BATS_DIR:-$out_dir/bats}"
  merge_bats_dirs_csv="${KCOV_MERGE_BATS_DIRS:-}"
  merge_coverage_dir="${KCOV_MERGE_COVERAGE_DIR:-$out_dir/coverage}"
  merge_wrapped_dir="${KCOV_MERGE_WRAPPED_DIR:-$out_dir/coverage-wrapped/kcov-merged}"

  merge_inputs=()
  if [[ -n "$merge_bats_dirs_csv" ]]; then
    IFS=',' read -r -a _merge_bats_dirs_parts <<<"$merge_bats_dirs_csv"
    for part in "${_merge_bats_dirs_parts[@]}"; do
      [[ -n "$part" ]] || continue
      merge_inputs+=("$part")
    done
    unset -v _merge_bats_dirs_parts
  else
    merge_inputs+=("$merge_bats_dir")
  fi
  merge_inputs+=("$merge_coverage_dir" "$merge_wrapped_dir")

  run_kcov_merge "merge" "$out_dir/kcov-merged" "${merge_inputs[@]}"
fi
