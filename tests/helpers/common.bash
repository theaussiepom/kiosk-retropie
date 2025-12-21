# Common test helpers for bats.

setup_test_root() {
	# Save original PATH so we can restore it during teardown.
	# Some tests intentionally set PATH to $TEST_ROOT/bin; after we delete TEST_ROOT,
	# leaving PATH pointing there can break bats' own cleanup.
	export RETRO_HA_TEST_ORIG_PATH="$PATH"

	# Repo root (for vendored libs, helpers, and stubs). Keep separate from
	# RETRO_HA_ROOT, which is the temp test root for scripts under test.
	if [[ -z "${RETRO_HA_REPO_ROOT:-}" ]]; then
		RETRO_HA_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
		export RETRO_HA_REPO_ROOT
	fi

	TEST_ROOT="$(mktemp -d)"
	export TEST_ROOT

	export RETRO_HA_ROOT="$TEST_ROOT"
	export RETRO_HA_CALLS_FILE="$TEST_ROOT/calls.log"

	# Suite-wide aggregation for path coverage assertions.
	export RETRO_HA_PATH_COVERAGE=1
	# Use a stable file so we can run tests individually (per-test timeout runner).
	export RETRO_HA_PATHS_FILE="${RETRO_HA_PATHS_FILE:-$RETRO_HA_REPO_ROOT/tests/.tmp/retro-ha-paths.log}"
	# Avoid depending on external dirname (PATH may be intentionally minimal).
	local paths_dir="${RETRO_HA_PATHS_FILE%/*}"
	if [[ -z "$paths_dir" || "$paths_dir" == "$RETRO_HA_PATHS_FILE" ]]; then
		paths_dir="."
	fi
	mkdir -p "$paths_dir"
	export RETRO_HA_CALLS_FILE_APPEND="$RETRO_HA_PATHS_FILE"

	mkdir -p "$TEST_ROOT/etc/retro-ha" "$TEST_ROOT/var/lib/retro-ha" "$TEST_ROOT/var/lock"

	# Ensure stubs override system commands.
	export PATH="$RETRO_HA_REPO_ROOT/tests/stubs:$PATH"
}

make_isolated_path_with_stubs() {
	# Create a temp bin dir containing only the requested stubs.
	# Usage: make_isolated_path_with_stubs systemctl getent curl
	local bin_dir="$TEST_ROOT/bin"
	mkdir -p "$bin_dir"

	# Provide a small set of core utilities that bats + our tests rely on.
	# Use symlinks to the real binaries (don't copy system binaries into $TEST_ROOT).
	# IMPORTANT: Do not add /bin to PATH here. On some distros /bin is a symlink to
	# /usr/bin, which would leak host tools (e.g. chromium) into "missing dependency"
	# tests.
	local core_tools=(
		env bash sh
		sleep
		cat rm mkdir rmdir mv cp ln chmod touch
		cut grep sed awk tr sort
		date mktemp head tail
	)
	local t src
	for t in "${core_tools[@]}"; do
		src=""
		if [[ -x "/bin/$t" ]]; then
			src="/bin/$t"
		elif [[ -x "/usr/bin/$t" ]]; then
			src="/usr/bin/$t"
		fi
		if [[ -n "$src" ]]; then
			ln -sf "$src" "$bin_dir/$t"
		fi
	done

	local stub
	for stub in "$@"; do
		cp "$RETRO_HA_REPO_ROOT/tests/stubs/$stub" "$bin_dir/$stub"
		chmod +x "$bin_dir/$stub"
	done

	# Expose only our curated toolset.
	export PATH="$bin_dir"
}

teardown_test_root() {
	# Restore a safe PATH before deleting $TEST_ROOT.
	if [[ -n "${RETRO_HA_TEST_ORIG_PATH:-}" ]]; then
		export PATH="$RETRO_HA_TEST_ORIG_PATH"
	fi

	if [[ -n "${TEST_ROOT:-}" && -d "${TEST_ROOT:-}" ]]; then
		rm -rf "$TEST_ROOT"
	fi
}

write_config_env() {
	local content="$1"
	local path="$TEST_ROOT/etc/retro-ha/config.env"
	printf '%s\n' "$content" >"$path"
	export RETRO_HA_CONFIG_ENV="$path"
}

# Convenience: assert a file contains a substring.
assert_file_contains() {
	local file="$1"
	local needle="$2"
	[[ -f "$file" ]] || return 1
	local grep_bin="grep"
	if [[ -x /usr/bin/grep ]]; then
		grep_bin="/usr/bin/grep"
	elif [[ -x /bin/grep ]]; then
		grep_bin="/bin/grep"
	fi
	"$grep_bin" -Fq -- "$needle" "$file"
}
