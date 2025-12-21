# GitHub Copilot instructions (retro-ha-appliance)

These instructions describe how this repo is structured, how CI runs, and what “good changes” look like.

If anything here conflicts with an explicit user request in the chat, follow the user request.

## 1) What this repo is

`retro-ha-appliance` is a Bash-first project that ships scripts + systemd units to run a RetroPie/Retro mode and a Home Assistant kiosk mode, plus some helper services (NFS sync, backups, MQTT state).

The codebase emphasizes:
- Script correctness and predictable behavior under `set -euo pipefail`
- Strict linting (ShellCheck, shfmt, yamllint, markdownlint)
- Test coverage via Bats (unit + integration)
- CI parity between local runs and GitHub Actions

## 2) Golden rule: run through the devcontainer

Do not assume host tools exist (e.g. `make` may be missing).

Preferred ways to run things:
- Full CI pipeline: `./scripts/ci.sh`
- One CI part: `./scripts/ci.sh lint-sh` (or other part names)
- Make targets (when available): `make lint`, `make test-unit`, `make test-integration`, `make ci`

The Makefile runs commands inside a Docker devcontainer image (`retro-ha-devcontainer:local`). If `docker` isn’t available, the Makefile may fall back to running locally.

## 3) CI/router model (important)

CI is intentionally routed through scripts so local + Actions behave the same:
- Entry: `./scripts/ci.sh`
- Router: `./ci/ci.sh`
- Parts: `./ci/NN-*.sh`

Valid parts are printed by the router when you pass an unknown part.

When making changes, prefer adding/modifying CI parts rather than duplicating logic in the workflow.

## 4) Lint expectations (no warnings)

This repo aims for “clean editor + clean CI”:
- ShellCheck should run clean on the files it checks (no warnings).
- shfmt should produce no diffs.
- yamllint and markdownlint should be clean.

Important nuance:
- Some files (like Bats tests) use dynamic `source`/`load` paths; in those cases, prefer *targeted* ShellCheck suppressions at the smallest reasonable scope.
  - Typical: `SC1090` / `SC1091` for dynamic sourcing
  - Bats-specific: `SC2030` / `SC2031` can appear due to how `@test` runs in a subshell

If a suppression is added, keep it narrowly scoped and explain it via the rule IDs (e.g. `# shellcheck disable=SC1090,SC1091`).

## 5) Formatting/style

Bash:
- Use `#!/usr/bin/env bash` and `set -euo pipefail` for scripts.
- Prefer explicit, readable names over abbreviations.
- Quote variables unless intentional word splitting is required.
- Avoid bashisms in `.sh` only when necessary; this repo is Bash-first.

shfmt rules (CI enforced):
- `-i 2 -ci -sr`

## 6) Tests (Bats)

Tests are under:
- `tests/unit/*.bats`
- `tests/integration/*.bats`

Vendored Bats libs are under:
- `tests/vendor/…`

Do not edit vendored code unless explicitly requested.

Bats patterns used here:
- Many tests compute `RETRO_HA_REPO_ROOT` and then `load` helper libraries.
- Environment variables are often used as test inputs, and may be consumed by sourced scripts.
  - If VS Code/ShellCheck reports “appears unused” for such vars, exporting them is usually the correct fix.

When adding helper functions inside a `.bats` file, define them before first usage to avoid “function defined later” diagnostics from editors.

## 7) Systemd units

Systemd units live under `systemd/`. CI may verify units using `systemd-analyze verify`.

When editing units:
- Keep names consistent with existing services.
- Avoid adding new services/units unless explicitly requested.

## 8) MQTT scripts

MQTT-related scripts live under:
- `scripts/leds/…`
- `scripts/screen/…`

When touching MQTT behavior:
- Be careful about retained messages/state.
- Keep payload handling strict and explicit.

## 9) “How to verify” checklist

Before considering a change complete:
- Run `./scripts/ci.sh lint-sh` for shell changes.
- Run unit tests: `./tests/bin/run-bats-unit.sh` (or `make test-unit`).
- Run integration tests when behavior changes: `./tests/bin/run-bats-integration.sh`.
- If you changed CI routing or workflows: run `./scripts/ci.sh`.
