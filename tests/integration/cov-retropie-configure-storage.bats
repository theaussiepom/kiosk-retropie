#!/usr/bin/env bats

# shellcheck disable=SC1090,SC1091

KIOSK_RETROPIE_REPO_ROOT="${KIOSK_RETROPIE_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"

load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-support/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/vendor/bats-assert/load"
load "$KIOSK_RETROPIE_REPO_ROOT/tests/helpers/common"

setup() {
	setup_test_root
	export KIOSK_RETROPIE_DRY_RUN=1
	export KIOSK_RETROPIE_ALLOW_NON_ROOT=1

	# Make getent return a home dir under the test root (script uses absolute home paths).
	export GETENT_PASSWD_RETROPI_LINE="retropi:x:1000:1000::${TEST_ROOT}/home/retropi:/bin/bash"

	mkdir -p "$TEST_ROOT/home/retropi/RetroPie"

	# Fake retropie home & retroarch config
	mkdir -p "$TEST_ROOT/opt/retropie/configs/all"
	echo "# test" > "$TEST_ROOT/opt/retropie/configs/all/retroarch.cfg"
}


teardown() {
	teardown_test_root
}

@test "configure-retropie-storage succeeds in dry-run" {
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/retropie/configure-retropie-storage.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "write_kv"
}

@test "configure-retropie-storage skips retroarch config when missing" {
	rm -f "$TEST_ROOT/opt/retropie/configs/all/retroarch.cfg"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/retropie/configure-retropie-storage.sh"
	assert_success
	/usr/bin/grep -Fq -- "RetroArch config not found" <<<"$output"
}

@test "configure-retropie-storage fails when not root and non-root is not allowed" {
	export KIOSK_RETROPIE_ALLOW_NON_ROOT=0
	export KIOSK_RETROPIE_DRY_RUN=1

	# This assertion is about the script's privilege check. Run the script under a
	# non-root UID even if the test suite itself is running as root (e.g. inside a
	# container).
	local script_src="$KIOSK_RETROPIE_REPO_ROOT/scripts/retropie/configure-retropie-storage.sh"
	local public_root
	public_root="$(mktemp -d)"
	chmod 755 "$public_root"
	local script_copy_dir="$public_root/scripts/retropie"
	mkdir -p "$script_copy_dir" "$public_root/scripts/lib"
	cp "$script_src" "$script_copy_dir/configure-retropie-storage.sh"
	cp "$KIOSK_RETROPIE_REPO_ROOT/scripts/lib/common.sh" "$public_root/scripts/lib/common.sh"
	cp "$KIOSK_RETROPIE_REPO_ROOT/scripts/lib/logging.sh" "$public_root/scripts/lib/logging.sh"
		cp "$KIOSK_RETROPIE_REPO_ROOT/scripts/lib/path.sh" "$public_root/scripts/lib/path.sh"
	chmod -R a+rX "$public_root"

	if [[ "${EUID:-$(id -u)}" -eq 0 ]] && command -v runuser >/dev/null 2>&1; then
		run runuser -u nobody -- bash "$script_copy_dir/configure-retropie-storage.sh"
	elif [[ "${EUID:-$(id -u)}" -eq 0 ]] && command -v su >/dev/null 2>&1; then
		run su -s /bin/bash nobody -c "bash '$script_copy_dir/configure-retropie-storage.sh'"
	else
		run bash "$script_copy_dir/configure-retropie-storage.sh"
	fi
	assert_failure
	assert_output --partial "Must run as root"
}

@test "configure-retropie-storage fails when retropi home cannot be resolved" {
	export KIOSK_RETROPIE_ALLOW_NON_ROOT=1
	export KIOSK_RETROPIE_DRY_RUN=1
	# Empty home dir field (6th field) so cut -f6 returns empty.
	export GETENT_PASSWD_RETROPI_LINE="retropi:x:1000:1000:::/bin/bash"

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/retropie/configure-retropie-storage.sh"
	assert_failure
	assert_output --partial "Unable to resolve home directory"
}

@test "configure-retropie-storage covers target existing + symlink branches" {
	export KIOSK_RETROPIE_ALLOW_NON_ROOT=1
	export KIOSK_RETROPIE_DRY_RUN=1

	# Use an isolated PATH so we can stub chown (no real retropi user required).
	make_isolated_path_with_stubs dirname getent id
	# kiosk_retropie_realpath_m uses python3; ensure it's available.
	if [[ -x /usr/bin/python3 ]]; then
		ln -sf /usr/bin/python3 "$TEST_ROOT/bin/python3"
	fi
	cat >"$TEST_ROOT/bin/chown" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$TEST_ROOT/bin/chown"

	# Make the existing target be a directory to force the mv-to-backup branch.
	mkdir -p "$TEST_ROOT/home/retropi/RetroPie/roms"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/retropie/configure-retropie-storage.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "mv"

	# Now make it a symlink to cover the -L branch.
	rm -rf "$TEST_ROOT/home/retropi/RetroPie/roms"
	ln -s "$TEST_ROOT/var/lib/kiosk-retropie/retropie/roms" "$TEST_ROOT/home/retropi/RetroPie/roms"
	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/retropie/configure-retropie-storage.sh"
	assert_success
}

@test "configure-retropie-storage ensure_kv_line covers existing-key edit path" {
	export KIOSK_RETROPIE_ALLOW_NON_ROOT=1
	export KIOSK_RETROPIE_DRY_RUN=1

	# Prepare a retroarch.cfg that already contains the key so ensure_kv_line takes the awk-replace branch.
	echo 'savefile_directory = "OLD"' > "$TEST_ROOT/opt/retropie/configs/all/retroarch.cfg"

	run bash "$KIOSK_RETROPIE_REPO_ROOT/scripts/retropie/configure-retropie-storage.sh"
	assert_success
	assert_file_contains "$TEST_ROOT/calls.log" "write_kv"
}
