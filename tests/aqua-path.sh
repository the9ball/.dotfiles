#!/usr/bin/env bash
# Run offline with bash tests/aqua-path.sh; no user configuration is modified.
set -eu

repository_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(cd "${TMPDIR:-/tmp}" && pwd -P)
test_directory=$(mktemp -d "$test_root/dotfiles-aqua-path.XXXXXX")
case "$test_directory" in
	"$test_root"/dotfiles-aqua-path.*) ;;
	*) printf 'Unexpected temporary directory: %s\n' "$test_directory" >&2; exit 1 ;;
esac
trap 'rm -rf -- "$test_directory"' EXIT
mkdir -p "$test_directory/home" "$test_directory/aqua root/bin" "$test_directory/competitor"
printf '#!/bin/sh\nexit 0\n' > "$test_directory/aqua root/bin/curl"
printf '#!/bin/sh\nexit 0\n' > "$test_directory/competitor/curl"
chmod +x "$test_directory/aqua root/bin/curl" "$test_directory/competitor/curl"
test_aqua_bin_directory="$test_directory/aqua root/bin"

# Assert two strings match without interpreting PATH entries as patterns.
assert_equal() {
	if [[ $1 != "$2" ]]; then
		printf 'FAIL %s\nexpected: <%s>\nactual:   <%s>\n' "$case_name" "$2" "$1" >&2
		exit 1
	fi
}

# Simulate aqua root discovery and record whether the external lookup was needed.
aqua() {
	assert_equal "$*" root-dir
	printf 'lookup\n' >> "$test_directory/lookup"
	[[ $case_name != root-failure ]] || return 1
	printf '%s\n' 'C:\aqua root'
}

# Simulate Windows path conversion, including rejected and failed conversions.
cygpath() {
	assert_equal "$1" -u
	assert_equal "$2" "$expected_native_root"
	case "$case_name" in
		conversion-failure) return 1 ;;
		empty-converted-root) printf '\n' ;;
		relative-root) printf 'relative/root\n' ;;
		unc-root) printf '//server/share\n' ;;
		colon-root) printf '/c/invalid:root\n' ;;
		*) printf '%s\n' "$test_directory/aqua root" ;;
	esac
}

# Hide only the selected prerequisite while retaining ordinary command lookup.
command() {
	if [[ ${1-} == -v ]]; then
		case "$case_name:${2-}" in
			missing-aqua:aqua|missing-cygpath:cygpath) return 1 ;;
		esac
	fi
	builtin command "$@"
}

# Source the actual startup file in an isolated HOME and check its observable behavior.
run_case() (
	case_name=$1
	PATH=$2
	expected_path=$3
	expected_native_root='C:\aqua root'
	HOME="$test_directory/home"
	OSTYPE=msys
	unset AQUA_ROOT_DIR XDG_DATA_HOME SSH_CONNECTION TMUX PSMUX_SESSION
	: > "$test_directory/lookup"
	case "$case_name" in
		explicit-root)
			AQUA_ROOT_DIR='D:\custom root'
			expected_native_root=$AQUA_ROOT_DIR
			;;
		empty-root) AQUA_ROOT_DIR= ;;
		linux|macos)
			OSTYPE=linux-gnu
			[[ $case_name != macos ]] || OSTYPE=darwin
			;;
	esac
	. "$repository_directory/.bashrc"
	assert_equal "$PATH" "$expected_path"
	case "$case_name" in
		explicit-root|missing-aqua|missing-cygpath|linux|macos)
			assert_equal "$(< "$test_directory/lookup")" ''
			;;
		*) assert_equal "$(< "$test_directory/lookup")" lookup ;;
	esac
	if [[ $case_name == selection ]]; then
		assert_equal "$(command -v curl)" "$test_aqua_bin_directory/curl"
	fi
	if [[ $case_name == repeated ]]; then
		. "$repository_directory/.bashrc"
		assert_equal "$PATH" "$expected_path"
	fi
	if [[ $case_name == linux || $case_name == macos ]]; then
		assert_equal "$AQUA_GLOBAL_CONFIG" "$HOME/.dotfiles/aqua.yaml"
	fi
	printf 'PASS %s\n' "$case_name"
)

run_case absent /usr/bin "$test_aqua_bin_directory:/usr/bin"
run_case first "$test_aqua_bin_directory:/usr/bin" "$test_aqua_bin_directory:/usr/bin"
run_case middle "/usr/bin:$test_aqua_bin_directory:/bin" "$test_aqua_bin_directory:/usr/bin:/bin"
run_case last "/usr/bin:$test_aqua_bin_directory" "$test_aqua_bin_directory:/usr/bin"
run_case duplicate "$test_aqua_bin_directory:/usr/bin:$test_aqua_bin_directory:$test_aqua_bin_directory" "$test_aqua_bin_directory:/usr/bin"
run_case only "$test_aqua_bin_directory" "$test_aqua_bin_directory"
run_case empty '' "$test_aqua_bin_directory:"
run_case empty-fields ":/usr/bin::$test_aqua_bin_directory:" "$test_aqua_bin_directory::/usr/bin::"
run_case literal-fields '/path with spaces:/literal*?[x]:/bin' "$test_aqua_bin_directory:/path with spaces:/literal*?[x]:/bin"
run_case repeated "/usr/bin:$test_aqua_bin_directory" "$test_aqua_bin_directory:/usr/bin"
run_case selection "$test_directory/competitor:/usr/bin" "$test_aqua_bin_directory:$test_directory/competitor:/usr/bin"
run_case explicit-root /usr/bin "$test_aqua_bin_directory:/usr/bin"
run_case empty-root /usr/bin "$test_aqua_bin_directory:/usr/bin"
for failure_case in missing-aqua missing-cygpath root-failure conversion-failure empty-converted-root relative-root unc-root colon-root; do
	run_case "$failure_case" /unchanged/path /unchanged/path
done
run_case linux /usr/bin "$test_directory/home/.local/share/aquaproj-aqua/bin:/usr/bin"
run_case macos /usr/bin "$test_directory/home/.local/share/aquaproj-aqua/bin:/usr/bin"

# Repeat failure cases without errexit to cover ordinary interactive-shell behavior.
set +e
for failure_case in missing-aqua missing-cygpath root-failure conversion-failure empty-converted-root relative-root unc-root colon-root; do
	run_case "$failure_case" /unchanged/path /unchanged/path || exit 1
done
