#!/usr/bin/env bash
set -euo pipefail

# Ensure a sane PATH even if the calling shell mutated it.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# Stable repo-root path for tests (avoids depending on $BATS_TEST_DIRNAME-relative paths).
export RETRO_HA_REPO_ROOT="$ROOT_DIR"

"$ROOT_DIR/tests/bin/fetch-bats.sh" >/dev/null

export BATS_LOAD_PATH="$ROOT_DIR/tests:$ROOT_DIR/tests/vendor"
export BATS_LIB_PATH="$ROOT_DIR/tests/vendor:$ROOT_DIR/tests"

if ! command -v kcov >/dev/null 2>&1; then
  echo "kcov not found on PATH" >&2
  exit 127
fi

out_dir="${KCOV_OUT_DIR:-$ROOT_DIR/coverage}"
rm -rf "$out_dir"
mkdir -p "$out_dir"

# Run the Bats suite under kcov to gather coverage for scripts/**.
# Prefer the explicit bash parser flag; older kcov versions use different names.
# Exclude tests and vendored bats libs.

kcov_help="$(kcov --help 2>&1 || true)"
bash_parser_flag=""
parse_dirs_flag=""
report_type_args=()
verbosity_args=()
kcov_arg_order="${KCOV_ARG_ORDER:-opts_first}"
if grep -Fq -- '--bash-parser' <<<"$kcov_help"; then
  bash_parser_flag="--bash-parser"
elif grep -Fq -- '--bash-parse' <<<"$kcov_help"; then
  # Avoid the ambiguous prefix '--bash-parse' (it can match multiple options).
  bash_parser_flag=""
fi

if grep -Fq -- '--bash-parse-files-in-dirs' <<<"$kcov_help"; then
  parse_dirs_flag="--bash-parse-files-in-dirs=$ROOT_DIR/scripts"
fi

# Some kcov versions only emit coverage.json when JSON reporting is explicitly enabled.
if grep -Fq -- '--report-type' <<<"$kcov_help"; then
  report_type_args+=(--report-type=html --report-type=json)
fi

if grep -Fq -- '--verbose' <<<"$kcov_help"; then
  verbosity_args+=(--verbose)
fi
if grep -Fq -- '--debug' <<<"$kcov_help"; then
  verbosity_args+=(--debug)
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
if [[ -n "$parse_dirs_flag" ]]; then
  common_args+=("$parse_dirs_flag")
fi
common_args+=(
  "${verbosity_args[@]}"
  "${report_type_args[@]}"
  --include-path="$ROOT_DIR/scripts"
  --exclude-pattern="$ROOT_DIR/tests,$ROOT_DIR/tests/vendor"
)

run_kcov() {
  local label="$1"
  local out="$2"
  local cmd="$3"
  shift 3

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

  echo "kcov step: $label" >&2
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
  # so we can proceed to driver+merge and still enforce coverage.
  if [[ "${KCOV_ALLOW_NONZERO_WITH_REPORT:-0}" == "1" && "$rc" -ne 0 ]]; then
    if find "$out" -maxdepth 4 -name coverage.json -print -quit 2>/dev/null | grep -q .; then
      echo "kcov step returned non-zero but produced coverage.json; continuing: $label (exit=$rc)" >&2
      return 0
    fi
  fi

  if [[ "$rc" -eq 124 ]]; then
    echo "kcov step timed out after ${timeout_seconds}s: $label" >&2
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

  echo "kcov step failed: $label (exit=$rc)" >&2
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
run_kcov "bats" "$out_dir/bats" "$ROOT_DIR/tests/bin/run-bats-integration.sh" "$@"

# Run additional “line coverage” driver paths under kcov.
run_kcov "driver" "$out_dir/driver" "$ROOT_DIR/tests/bin/kcov-line-coverage-driver.sh"

# Merge into a stable location consumed by assert-kcov-100.sh.
run_kcov_merge "merge" "$out_dir/kcov-merged" "$out_dir/bats" "$out_dir/driver"
