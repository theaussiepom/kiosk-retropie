SHELL := /usr/bin/env bash

.PHONY: help tools \
  container-build container-shell container-run \
	lint lint-sh lint-yaml lint-systemd lint-markdown \
  format format-shell \
  test test-unit test-integration path-coverage coverage \
	ci

DOCKER ?= docker
DEVCONTAINER_IMAGE ?= retro-ha-devcontainer:local
DEVCONTAINER_DOCKERFILE ?= .devcontainer/Dockerfile
DEVCONTAINER_CONTEXT ?= .
DEVCONTAINER_WORKDIR ?= /work

container-build:
	@if command -v "$(DOCKER)" >/dev/null 2>&1; then \
		$(DOCKER) build -t "$(DEVCONTAINER_IMAGE)" -f "$(DEVCONTAINER_DOCKERFILE)" "$(DEVCONTAINER_CONTEXT)"; \
	else \
		echo "docker not found; skipping container build" >&2; \
	fi

container-shell:
	@if ! command -v "$(DOCKER)" >/dev/null 2>&1; then \
		echo "docker not found; container-shell requires Docker on the host" >&2; \
		exit 2; \
	fi; \
	$(DOCKER) run --rm -it \
		-v "$(CURDIR):$(DEVCONTAINER_WORKDIR)" \
		-w "$(DEVCONTAINER_WORKDIR)" \
		"$(DEVCONTAINER_IMAGE)" \
		bash

# Internal helper: run a command inside the devcontainer.
# Usage: make container-run CMD='echo hi'
container-run: container-build
	@[ -n "$(CMD)" ] || { echo "CMD is required (e.g. make container-run CMD='./scripts/ci.sh')" >&2; exit 2; }
	@if command -v "$(DOCKER)" >/dev/null 2>&1; then \
		$(DOCKER) run --rm \
			-v "$(CURDIR):$(DEVCONTAINER_WORKDIR)" \
			-w "$(DEVCONTAINER_WORKDIR)" \
			"$(DEVCONTAINER_IMAGE)" \
			bash -lc "$(CMD)"; \
	else \
		echo "docker not found; running command locally" >&2; \
		bash -lc "$(CMD)"; \
	fi

help:
	@echo "Targets:"
	@echo "  container-build Build the devcontainer image ($(DEVCONTAINER_IMAGE))"
	@echo "  container-shell Start an interactive shell in the devcontainer"
	@echo "  ci            Run the full CI pipeline in the devcontainer (matches GitHub Actions)"
	@echo "  lint          Run all lint checks (permissions + naming + lint-*) in one devcontainer run"
	@echo "  test          Run all bats tests in the devcontainer"
	@echo "  test-unit     Run unit bats tests only"
	@echo "  test-integration Run integration bats tests only (includes path coverage check)"
	@echo "  path-coverage Run path coverage summary (runs tests then prints counts)"
	@echo "  coverage      Run kcov coverage in the devcontainer"
	@echo "  format        Auto-format where safe (shell scripts; host toolchain)"
	@echo "  lint-sh       bash -n + shellcheck + shfmt -d"
	@echo "  lint-yaml     yamllint"
	@echo "  lint-systemd  systemd-analyze verify"
	@echo "  lint-markdown markdownlint"

test:
	@$(MAKE) container-run CMD='./scripts/ci.sh tests'

test-unit:
	@$(MAKE) container-run CMD='./tests/bin/run-bats-unit.sh'

test-integration:
	@$(MAKE) container-run CMD='./tests/bin/run-bats-integration.sh'

path-coverage:
	@$(MAKE) container-run CMD='./tests/bin/recalc-path-coverage.sh --run'

coverage:
	@$(MAKE) container-run CMD='./scripts/ci.sh coverage'

# Optional helper. Use what you already have installed if you prefer.
tools:
	@echo "Install tools as needed:"
	@echo "  - shellcheck"
	@echo "  - shfmt"
	@echo "  - yamllint (pip install yamllint)"
	@echo "  - markdownlint-cli (npm i -g markdownlint-cli)"
	@echo "  - systemd-analyze (already on Linux; CI provides it)"
	@echo ""
	@echo "No automatic install performed."

# Run all linters in one container (faster than multiple container runs).
lint:
	@$(MAKE) container-run CMD='./scripts/ci.sh lint-permissions lint-naming lint-sh lint-yaml lint-systemd lint-markdown'

# Runs the same checks as GitHub Actions.
# Note: systemd-analyze verify checks that ExecStart binaries exist.
# In CI we create minimal stubs under /usr/local; the CI script does the same.
ci:
	@$(MAKE) container-run CMD='./scripts/ci.sh'

lint-sh:
	@$(MAKE) container-run CMD='./scripts/ci.sh lint-sh'

lint-yaml:
	@$(MAKE) container-run CMD='./scripts/ci.sh lint-yaml'

lint-systemd:
	@$(MAKE) container-run CMD='./scripts/ci.sh lint-systemd'

lint-markdown:
	@$(MAKE) container-run CMD='./scripts/ci.sh lint-markdown'

format: format-shell

format-shell:
	@files=(); \
	if [ -d scripts ]; then \
	  while IFS= read -r -d '' f; do files+=("$$f"); done < <(find scripts -type f -name '*.sh' -print0); \
	fi; \
	if [ $${#files[@]} -eq 0 ]; then \
	  echo "No shell scripts found under scripts/"; \
	  exit 0; \
	fi; \
	echo "Formatting shell scripts with shfmt..."; \
	shfmt -w -i 2 -ci -sr "$${files[@]}"
