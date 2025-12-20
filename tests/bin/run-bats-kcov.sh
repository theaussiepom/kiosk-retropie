#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

"$ROOT_DIR/tests/bin/fetch-bats.sh" >/dev/null

export BATS_LIB_PATH="$ROOT_DIR/tests/vendor"

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
kcov_arg_order="opts_first"
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

# kcov CLI argument order varies across versions/packages.
# Some expect: kcov [options] outdir command...
# Others expect: kcov outdir [options] command...
if grep -Eq '^Usage:.*kcov[[:space:]]+\[options\][[:space:]]+[^ ]*out' <<<"$usage_line"; then
  kcov_arg_order="opts_first"
elif grep -Eq '^Usage:.*kcov[[:space:]]+[^ ]*out[^ ]*[[:space:]]+\[options\]' <<<"$usage_line"; then
  kcov_arg_order="out_first"
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

  # Primary cmd based on detected order; keep a fallback to handle distros where
  # help/usage formatting differs from what we expect.
  local -a kcov_cmd
  mapfile -t kcov_cmd < <(build_kcov_cmd "$kcov_arg_order")
  local alt_order="opts_first"
  if [[ "$kcov_arg_order" == "opts_first" ]]; then
    alt_order="out_first"
  fi
  local -a kcov_cmd_alt
  mapfile -t kcov_cmd_alt < <(build_kcov_cmd "$alt_order")

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

  # If kcov failed quickly and didn't tell us why, try the alternate CLI order
  # once. This is cheap in the failure mode we see on CI (silent exit=1).
  local log_size=0
  log_size="$(wc -c <"$log_file" 2>/dev/null || echo 0)"
  if [[ "$log_size" -lt 200 ]]; then
    local alt_log_file="$out_dir/${label}.alt.log"
    echo "kcov produced little/no output; retrying with arg order: $alt_order" >&2
    echo "+ ${kcov_cmd_alt[*]}" >&2
    if run_one kcov_cmd_alt "$alt_log_file"; then
      mv "$alt_log_file" "$log_file"
      return 0
    fi
    # Keep rc from the alternate run if it produced a clearer failure.
    rc=$?
    if [[ -s "$alt_log_file" ]]; then
      mv "$alt_log_file" "$log_file"
    fi
  fi

  if [[ "$rc" -eq 124 ]]; then
    echo "kcov step timed out after ${timeout_seconds}s: $label" >&2
  fi

  # If kcov failed but produced no output, capture a small strace to help debug
  # CI-only failures. Keep it narrow to avoid massive artifacts.
  if [[ ! -s "$log_file" ]] || [[ "$(wc -c <"$log_file" 2>/dev/null || echo 0)" -lt 200 ]]; then
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
run_kcov "bats" "$out_dir/bats" "$ROOT_DIR/tests/bin/run-bats.sh" "$@"

# Run additional “line coverage” driver paths under kcov.
run_kcov "driver" "$out_dir/driver" "$ROOT_DIR/tests/bin/kcov-line-coverage-driver.sh"

# Merge into a stable location consumed by assert-kcov-100.sh.
run_kcov_merge "merge" "$out_dir/kcov-merged" "$out_dir/bats" "$out_dir/driver"
