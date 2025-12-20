#!/usr/bin/env bats

RETRO_HA_REPO_ROOT="${RETRO_HA_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-support/load"
load "$RETRO_HA_REPO_ROOT/tests/vendor/bats-assert/load"

@test "path coverage: all required path IDs were hit" {
  required_file="$RETRO_HA_REPO_ROOT/tests/coverage/required-paths.txt"
  paths_log="${RETRO_HA_PATHS_FILE:-$RETRO_HA_REPO_ROOT/tests/.tmp/retro-ha-paths.unit.log}"

  [ -f "$required_file" ]
  [ -f "$paths_log" ]

  missing=()
  while IFS= read -r line; do
    case "$line" in
      ''|'#'*) continue ;;
    esac

    # Unit scope: enforce only library IDs.
    case "$line" in
      lib-*) ;;
      *) continue ;;
    esac

    # Match exact token "PATH <id>" in the log.
    if ! /usr/bin/grep -Fq -- "PATH $line" "$paths_log"; then
      missing+=("$line")
    fi
  done < "$required_file"

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "Missing path coverage ids (${#missing[@]}):" >&2
    printf '%s\n' "${missing[@]}" >&2
    return 1
  fi
}
