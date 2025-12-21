#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    return 1
  fi
}

shopt -s globstar nullglob

echo "== shell: bash -n =="
shell_files=(scripts/**/*.sh)
if [ ${#shell_files[@]} -eq 0 ]; then
  echo "No shell scripts found under scripts/**/*.sh, skipping."
else
  for f in "${shell_files[@]}"; do
    echo "bash -n $f"
    bash -n "$f"
  done
fi

echo "== shell: shellcheck =="
require_cmd shellcheck
if [ ${#shell_files[@]} -eq 0 ]; then
  echo "No shell scripts found under scripts/**/*.sh, skipping."
else
  shellcheck "${shell_files[@]}"
fi

echo "== shell: shfmt =="
require_cmd shfmt
if [ ${#shell_files[@]} -eq 0 ]; then
  echo "No shell scripts found under scripts/**/*.sh, skipping."
else
  shfmt -d -i 2 -ci -sr "${shell_files[@]}"
fi

echo "== tests: bats =="
"$repo_root/tests/bin/run-bats.sh"

echo "== yaml: yamllint =="
require_cmd yamllint
yaml_files=(
  .github/**/*.yml
  .github/**/*.yaml
  cloud-init/**/*.yml
  cloud-init/**/*.yaml
  examples/**/*.yml
  examples/**/*.yaml
)
existing_yaml=()
for f in "${yaml_files[@]}"; do
  [ -f "$f" ] && existing_yaml+=("$f") || true
done
if [ ${#existing_yaml[@]} -eq 0 ]; then
  echo "No YAML files found in expected locations, skipping."
else
  yamllint -c .yamllint.yml "${existing_yaml[@]}"
fi

echo "== systemd: systemd-analyze verify =="
require_cmd systemd-analyze
# systemd-analyze verify checks that ExecStart binaries exist.
# Mirror CI by creating minimal executable stubs for referenced /usr/local paths.
if command -v sudo >/dev/null 2>&1; then
  execs=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    execs+=("${line#*=}")
  done < <(grep -hoE '^(ExecStart|ExecStartPre)=[^ ]+' systemd/**/*.service 2>/dev/null | sort -u || true)

  for exe in "${execs[@]}"; do
    case "$exe" in
      /usr/local/*)
        sudo mkdir -p "$(dirname "$exe")"
        printf '%s\n' '#!/usr/bin/env bash' 'exit 0' | sudo tee "$exe" >/dev/null
        sudo chmod +x "$exe"
        ;;
    esac
  done
else
  echo "sudo not found; systemd unit verification may fail if /usr/local ExecStart paths do not exist." >&2
fi

unit_files=(
  systemd/**/*.service
  systemd/**/*.timer
  systemd/**/*.target
  systemd/**/*.path
  systemd/**/*.socket
  systemd/**/*.mount
)
existing_units=()
for u in "${unit_files[@]}"; do
  [ -f "$u" ] && existing_units+=("$u") || true
done
if [ ${#existing_units[@]} -eq 0 ]; then
  echo "No systemd unit files found under systemd/, skipping."
else
  for u in "${existing_units[@]}"; do
    echo "systemd-analyze verify $u"
    systemd-analyze verify "$u"
  done
fi

echo "== markdown: markdownlint =="
require_cmd markdownlint
md_files=(
  README.md
  CHANGELOG.md
  CONTRIBUTING.md
  CODE_OF_CONDUCT.md
  docs/**/*.md
)
existing_md=()
for f in "${md_files[@]}"; do
  [ -f "$f" ] && existing_md+=("$f") || true
done
if [ ${#existing_md[@]} -eq 0 ]; then
  echo "No markdown files found, skipping."
else
  markdownlint -c .markdownlint.json "${existing_md[@]}"
fi

echo "== coverage: kcov =="
require_cmd kcov
require_cmd strace
KCOV_ALLOW_NONZERO_WITH_REPORT=1 "$repo_root/tests/bin/run-bats-kcov.sh"
"$repo_root/tests/bin/assert-kcov-100.sh"

echo "== done =="
