#!/usr/bin/env bash
# Run with Git Bash: bash --noprofile --norc -i tests/ssh-psmux.sh (a terminal is required).
set -eu

if [[ $- != *i* ]] || [[ ! -t 0 || ! -t 1 ]]; then
	printf '%s\n' 'Run this test in an interactive Git Bash terminal.' >&2
	exit 1
fi

repository_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
hook_path="$repository_directory/.bashrc.ssh-psmux"
test_directory=$(mktemp -d)
original_path=$PATH
export PSMUX_TEST_LOG="$test_directory/calls"
cat > "$test_directory/psmux" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PSMUX_TEST_LOG"
exit "${PSMUX_TEST_EXIT:-0}"
STUB
chmod +x "$test_directory/psmux"

# cleanup removes only the files created by this test, without recursive deletion.
cleanup() {
	rm -f "$test_directory/psmux" "$test_directory/calls" "$test_directory/.psmux-no-autoattach" "$test_directory/output"
	rmdir "$test_directory"
}
trap cleanup EXIT

# run_case isolates shell variables and asserts whether the hook invokes psmux.
run_case() (
	local scenario=$1 expected_calls=$2
	local HOME=$test_directory PATH="$test_directory:$original_path"
	local OSTYPE=msys SSH_CONNECTION='127.0.0.1 12345 127.0.0.1 22'
	local SHLVL=1
	local TMUX= PSMUX_SESSION= PSMUX_SSH_AUTOATTACH= BASH_EXECUTION_STRING=
	local __dotfiles_psmux_autoattach_attempted=
	export PATH HOME SSH_CONNECTION
	: > "$PSMUX_TEST_LOG"
	case "$scenario" in
		local) SSH_CONNECTION= ;;
		linux) OSTYPE=linux-gnu ;;
		tmux) TMUX='/tmp/psmux-test,1,0' ;;
		psmux) PSMUX_SESSION=main ;;
		bypass-env) PSMUX_SSH_AUTOATTACH=0 ;;
		bypass-file) touch "$HOME/.psmux-no-autoattach" ;;
		command) BASH_EXECUTION_STRING='printf command' ;;
		nested) SHLVL=2 ;;
		missing) PATH=/nonexistent ;;
		failure) export PSMUX_TEST_EXIT=42 ;;
	esac
	case "$scenario" in
		input-pipe) source "$hook_path" </dev/null ;;
		output-pipe) source "$hook_path" > "$test_directory/output" ;;
		noninteractive) bash --noprofile --norc -c 'source "$1"' bash "$hook_path" ;;
		interactive-command) SHLVL=0 bash --noprofile --rcfile "$hook_path" -ic 'printf "remote-command-ok\n"' ;;
		*) source "$hook_path" ;;
	esac
	if [[ $scenario == repeat ]]; then source "$hook_path"; fi
	PATH=$original_path
	local actual_calls
	actual_calls=$(wc -l < "$PSMUX_TEST_LOG")
	if [[ $actual_calls -ne $expected_calls ]]; then
		printf 'FAIL %s: expected %s calls, got %s\n' "$scenario" "$expected_calls" "$actual_calls" >&2
		exit 1
	fi
	if [[ $expected_calls == 1 ]] && [[ $(cat "$PSMUX_TEST_LOG") != 'new-session -A -s main' ]]; then
		printf 'FAIL %s: unexpected psmux arguments\n' "$scenario" >&2
		exit 1
	fi
	rm -f "$test_directory/.psmux-no-autoattach"
	printf 'PASS %s\n' "$scenario"
)

run_case attach 1
run_case repeat 1
run_case failure 1
for scenario in local linux tmux psmux bypass-env bypass-file command nested missing input-pipe output-pipe noninteractive interactive-command; do
	run_case "$scenario" 0
done
