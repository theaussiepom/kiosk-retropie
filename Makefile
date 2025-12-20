SHELL := /usr/bin/env bash

.PHONY: help tools lint lint-shell lint-yaml lint-systemd lint-markdown format format-shell test test-unit test-integration path-coverage coverage

help:
	@echo "Targets:"
	@echo "  tools         Install local lint tools (Linux/macOS with brew/apt) - optional"
	@echo "  lint          Run all linters (matches CI)"
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
