#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== lint-systemd: systemd-analyze verify =="
ci_require_cmd systemd-analyze

mapfile -d '' service_files < <(ci_list_service_files || true)
mapfile -d '' unit_files < <(ci_list_unit_files || true)

if [[ ${#unit_files[@]} -eq 0 ]]; then
  echo "No systemd unit files found under systemd/, skipping."
  exit 0
fi

# systemd-analyze verify checks that ExecStart binaries exist.
# Mirror GitHub CI by creating minimal executable stubs for referenced /usr/local paths.
if command -v sudo > /dev/null 2>&1; then
  execs=()
  if [[ ${#service_files[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      execs+=("${line#*=}")
    done < <(grep -hoE '^(ExecStart|ExecStartPre)=[^ ]+' "${service_files[@]}" 2> /dev/null | sort -u || true)
  fi

  exe=""
  for exe in "${execs[@]}"; do
    case "$exe" in
      /usr/local/*)
        sudo mkdir -p "$(dirname "$exe")"
        printf '%s\n' '#!/usr/bin/env bash' 'exit 0' | sudo tee "$exe" > /dev/null
        sudo chmod +x "$exe"
        ;;
    esac
  done
else
  echo "sudo not found; systemd unit verification may fail if /usr/local ExecStart paths do not exist." >&2
fi

u=""
for u in "${unit_files[@]}"; do
  echo "systemd-analyze verify $u"
  systemd-analyze verify "$u"
done
