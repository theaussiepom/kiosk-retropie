#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"

merge_input_dir() {
	echo "$KIOSK_RETROPIE_REPO_ROOT/tests/.tmp/kcov-merge-input"
}

setup() {
	mkdir -p "$KIOSK_RETROPIE_REPO_ROOT/tests/.tmp"
	rm -rf "$(merge_input_dir)"
	unset -v KIOSK_RETROPIE_CI_COVERAGE_MERGE_DRY_RUN
	unset -v KIOSK_RETROPIE_CI_COVERAGE_MERGE_RUNNER
}

default_merge_input_tree() {
	local root
	root="$(merge_input_dir)"

	mkdir -p "$root/bats-unit/out"
	touch "$root/bats-unit/out/index.html"

	mkdir -p "$root/bats-integration/out"
	touch "$root/bats-integration/out/index.html"

	mkdir -p "$root/somewhere/coverage-wrapped/kcov-merged"

	mkdir -p "$root/kcov-line-coverage.sh.ABC123/leaf"
	touch "$root/kcov-line-coverage.sh.ABC123/index.html"
	touch "$root/kcov-line-coverage.sh.ABC123/leaf/coverage.json"
}

teardown() {
	rm -rf "$(merge_input_dir)"
}

@test "ci coverage merge helper fails when merge input dir missing" {
	rm -rf "$(merge_input_dir)"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/ci/coverage-merge.sh"
	assert_failure
	assert_output --partial "KCOV merge input dir does not exist"
}

@test "ci coverage merge helper fails when bats unit index missing" {
	mkdir -p "$(merge_input_dir)/bats-unit"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/ci/coverage-merge.sh"
	assert_failure
	assert_output --partial "Could not locate bats unit kcov output"
}

@test "ci coverage merge helper fails when bats integration index missing" {
	mkdir -p "$(merge_input_dir)/bats-unit/out"
	touch "$(merge_input_dir)/bats-unit/out/index.html"
	mkdir -p "$(merge_input_dir)/bats-integration"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/ci/coverage-merge.sh"
	assert_failure
	assert_output --partial "Could not locate bats integration kcov output"
}

@test "ci coverage merge helper fails when wrapped merge dir missing" {
	mkdir -p "$(merge_input_dir)/bats-unit/out"
	touch "$(merge_input_dir)/bats-unit/out/index.html"
	mkdir -p "$(merge_input_dir)/bats-integration/out"
	touch "$(merge_input_dir)/bats-integration/out/index.html"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/ci/coverage-merge.sh"
	assert_failure
	assert_output --partial "Could not locate scripts wrapped merge dir"
}

@test "ci coverage merge helper fails when scripts coverage.json missing" {
	mkdir -p "$(merge_input_dir)/bats-unit/out"
	touch "$(merge_input_dir)/bats-unit/out/index.html"
	mkdir -p "$(merge_input_dir)/bats-integration/out"
	touch "$(merge_input_dir)/bats-integration/out/index.html"
	mkdir -p "$(merge_input_dir)/somewhere/coverage-wrapped/kcov-merged"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/ci/coverage-merge.sh"
	assert_failure
	assert_output --partial "Could not locate scripts kcov-line coverage.json"
}

@test "ci coverage merge helper fails when scripts index.html missing" {
	default_merge_input_tree
	rm -f "$(merge_input_dir)/kcov-line-coverage.sh.ABC123/index.html"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/ci/coverage-merge.sh"
	assert_failure
	assert_output --partial "Could not locate scripts kcov-line index.html"
}

@test "ci coverage merge helper supports dry-run" {
	default_merge_input_tree
	export KIOSK_RETROPIE_CI_COVERAGE_MERGE_DRY_RUN=1
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/ci/coverage-merge.sh"
	assert_success
	assert_output --partial "KCOV merge discovery dry-run"
	assert_output --partial "KCOV_MERGE_BATS_DIRS="
	assert_output --partial "KCOV_MERGE_COVERAGE_DIR="
	assert_output --partial "KCOV_MERGE_WRAPPED_DIR="
}

@test "ci coverage merge helper runs merge runner when provided" {
	default_merge_input_tree
	chmod +x "$KIOSK_RETROPIE_REPO_ROOT/tests/stubs/ci-coverage-merge-runner-ok"
	export KIOSK_RETROPIE_CI_COVERAGE_MERGE_RUNNER="$KIOSK_RETROPIE_REPO_ROOT/tests/stubs/ci-coverage-merge-runner-ok"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/ci/coverage-merge.sh"
	assert_success
}
