SHELL := /usr/bin/env bash

.PHONY: help tools lint lint-shell lint-yaml lint-systemd lint-systemd-ci lint-markdown format format-shell test test-unit test-integration path-coverage coverage ci ci-lint

help:
	@echo "Targets:"
	@echo "  tools         Install local lint tools (Linux/macOS with brew/apt) - optional"
	@echo "  lint          Run all linters (matches CI)"
	@echo "  ci            Run the full CI pipeline locally (lint + tests + kcov coverage)"
	@echo "  test          Run all bats tests (fetches bats into tests/vendor)"
	@echo "  test-unit     Run unit bats tests only"
	@echo "  test-integration Run integration bats tests only (includes path coverage check)"
	@echo "  path-coverage Run path coverage summary (runs tests then prints counts)"
	@echo "  format        Auto-format where safe (shell scripts)"
	@echo "  lint-shell    bash -n + shellcheck + shfmt -d"
	@echo "  lint-yaml     yamllint"
	@echo "  lint-systemd  systemd-analyze verify"
	@echo "  lint-markdown markdownlint"

test:
	@./tests/bin/run-bats.sh

test-unit:
	@./tests/bin/run-bats-unit.sh

test-integration:
	@./tests/bin/run-bats-integration.sh

path-coverage:
	@./tests/bin/recalc-path-coverage.sh --run

coverage:
	@./tests/bin/run-bats-kcov.sh
	@./tests/bin/assert-kcov-100.sh

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

lint: lint-shell lint-yaml lint-systemd lint-markdown

# Runs the same checks as GitHub Actions.
# Note: systemd-analyze verify checks that ExecStart binaries exist.
# In CI we create minimal stubs under /usr/local; `lint-systemd-ci` does the same.
ci: ci-lint test coverage

ci-lint: lint-shell lint-yaml lint-systemd-ci lint-markdown

lint-shell:
	@files=(); \
	if [ -d scripts ]; then \
	  while IFS= read -r -d '' f; do files+=("$$f"); done < <(find scripts -type f -name '*.sh' -print0); \
	fi; \
	if [ $${#files[@]} -eq 0 ]; then \
	  echo "No shell scripts found under scripts/"; \
	  exit 0; \
	fi; \
	echo "Running bash -n..."; \
	for f in "$${files[@]}"; do bash -n "$$f"; done; \
	echo "Running shellcheck..."; \
	shellcheck "$${files[@]}"; \
	echo "Running shfmt check..."; \
	shfmt -d -i 2 -ci -sr "$${files[@]}"

lint-yaml:
	@existing=(); \
	for d in .github cloud-init examples; do \
	  if [ -d "$$d" ]; then \
	    while IFS= read -r -d '' f; do existing+=("$$f"); done < <(find "$$d" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0); \
	  fi; \
	done; \
	if [ $${#existing[@]} -eq 0 ]; then \
	  echo "No YAML files found in expected locations"; \
	  exit 0; \
	fi; \
	yamllint -c .yamllint.yml "$${existing[@]}"

lint-systemd:
	@existing=(); \
	if [ -d systemd ]; then \
	  while IFS= read -r -d '' u; do existing+=("$$u"); done < <(find systemd -type f \( \
	    -name '*.service' -o -name '*.timer' -o -name '*.target' -o -name '*.path' -o -name '*.socket' -o -name '*.mount' \
	  \) -print0); \
	fi; \
	if [ $${#existing[@]} -eq 0 ]; then \
	  echo "No systemd unit files found under systemd/"; \
	  exit 0; \
	fi; \
	for u in "$${existing[@]}"; do \
	  echo "Verifying $$u"; \
	  systemd-analyze verify "$$u"; \
	done

lint-systemd-ci:
	@set -euo pipefail; \
	shopt -s globstar nullglob; \
	if ! command -v systemd-analyze >/dev/null 2>&1; then \
	  echo "Missing systemd-analyze"; \
	  exit 1; \
	fi; \
	if ! command -v sudo >/dev/null 2>&1; then \
	  echo "Missing sudo (needed to create /usr/local ExecStart stubs for systemd-analyze verify)"; \
	  exit 1; \
	fi; \
	execs=(); \
	while IFS= read -r line; do \
	  [[ -n "$$line" ]] || continue; \
	  execs+=("$${line#*=}"); \
	done < <(grep -hoE '^(ExecStart|ExecStartPre)=[^ ]+' systemd/**/*.service 2>/dev/null | sort -u || true); \
	for exe in "$${execs[@]}"; do \
	  case "$$exe" in \
	    /usr/local/*) \
	      sudo mkdir -p "$$(dirname "$$exe")"; \
	      printf '%s\n' '#!/usr/bin/env bash' 'exit 0' | sudo tee "$$exe" >/dev/null; \
	      sudo chmod +x "$$exe"; \
	      ;; \
	  esac; \
	done; \
	units=(systemd/**/*.service systemd/**/*.timer systemd/**/*.target systemd/**/*.path systemd/**/*.socket systemd/**/*.mount); \
	existing=(); \
	for u in "$${units[@]}"; do \
	  [ -f "$$u" ] && existing+=("$$u") || true; \
	done; \
	if [ $${#existing[@]} -eq 0 ]; then \
	  echo "No systemd unit files found under systemd/"; \
	  exit 0; \
	fi; \
	for u in "$${existing[@]}"; do \
	  echo "systemd-analyze verify $$u"; \
	  systemd-analyze verify "$$u"; \
	done

lint-markdown:
	@existing=(); \
	for f in README.md CHANGELOG.md CONTRIBUTING.md CODE_OF_CONDUCT.md; do \
	  [ -f "$$f" ] && existing+=("$$f") || true; \
	done; \
	if [ -d docs ]; then \
	  while IFS= read -r -d '' f; do existing+=("$$f"); done < <(find docs -type f -name '*.md' -print0); \
	fi; \
	if [ $${#existing[@]} -eq 0 ]; then \
	  echo "No markdown files found"; \
	  exit 0; \
	fi; \
	markdownlint -c .markdownlint.json "$${existing[@]}"

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
