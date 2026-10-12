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
export PSMUX_TEST_OVERLAY_LOG="$test_directory/overlay-calls"
export PSMUX_TEST_ENVIRONMENT_LOG="$test_directory/environment"
export PSMUX_TEST_REPOSITORY_DIRECTORY="$repository_directory"
cat > "$test_directory/psmux" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PSMUX_TEST_LOG"
exit "${PSMUX_TEST_EXIT:-0}"
STUB
chmod +x "$test_directory/psmux"

# cleanup removes only the files created by this test, without recursive deletion.
cleanup() {
	rm -f "$test_directory/psmux" "$test_directory/calls" "$test_directory/.psmux-no-autoattach" "$test_directory/output" "$test_directory/.bashrc.ssh"
	rm -f "$test_directory/overlay-calls" "$test_directory/environment"
	rmdir "$test_directory"
}
trap cleanup EXIT

# run_case checks overlay selection and observable child environments without reattachment.
run_case() (
	local scenario=$1 expected_calls=$2 expected_overlay=$3
	local HOME=$test_directory PATH="$test_directory:$original_path"
	local OSTYPE=msys SSH_CONNECTION='127.0.0.1 12345 127.0.0.1 22'
	local SHLVL=1
	local TMUX= PSMUX_SESSION= PSMUX_SSH_AUTOATTACH= BASH_EXECUTION_STRING=
	local __dotfiles_psmux_autoattach_attempted=
	local CODEX_HOME=existing
	local GH_CONFIG_DIR=existing-gh
	export PATH HOME SSH_CONNECTION TMUX PSMUX_SESSION CODEX_HOME GH_CONFIG_DIR
	cat > "$HOME/.bashrc.ssh" <<'OVERLAY'
printf 'loaded\n' >> "$PSMUX_TEST_OVERLAY_LOG"
source "$PSMUX_TEST_REPOSITORY_DIRECTORY/.bashrc.ssh"
printf '%s\n' "$CODEX_HOME" "$GH_CONFIG_DIR" > "$PSMUX_TEST_ENVIRONMENT_LOG"
OVERLAY
	: > "$PSMUX_TEST_LOG"
	: > "$PSMUX_TEST_OVERLAY_LOG"
	: > "$PSMUX_TEST_ENVIRONMENT_LOG"
	case "$scenario" in
		local) SSH_CONNECTION= ;;
		linux) OSTYPE=linux-gnu ;;
		linux-psmux) OSTYPE=linux-gnu; PSMUX_SESSION=main ;;
		tmux) TMUX='/tmp/tmux-1000/default,1,0' ;;
		psmux) PSMUX_SESSION=main ;;
		psmux-local) PSMUX_SESSION=main; SSH_CONNECTION= ;;
		psmux-command|psmux-noninteractive|psmux-interactive-command|psmux-input-pipe|psmux-output-pipe|psmux-reload) PSMUX_SESSION=main; SSH_CONNECTION= ;;
		psmux-custom) PSMUX_SESSION=work; SSH_CONNECTION= ;;
		psmux-socket) TMUX=/tmp/psmux-123/default,456,0; SSH_CONNECTION= ;;
		psmux-missing-overlay) PSMUX_SESSION=main; rm -f "$HOME/.bashrc.ssh" ;;
		ssh-pane) PSMUX_SESSION=ssh; TMUX=/tmp/psmux-123/dotfiles-ssh,456,0; SSH_CONNECTION= ;;
		warm-pane) PSMUX_SESSION=__warm__; TMUX=/tmp/psmux-123/dotfiles-ssh,456,0; SSH_CONNECTION= ;;
		warm-nested-pane) PSMUX_SESSION=__warm__; TMUX=/tmp/psmux-123/dotfiles-ssh,456,0; SHLVL=2 ;;
		warm-other-socket) PSMUX_SESSION=__warm__; TMUX=/tmp/psmux-123/default,456,0 ;;
		warm-no-socket) PSMUX_SESSION=__warm__ ;;
		stale-pane) PSMUX_SESSION=ssh; TMUX=/tmp/psmux-123/dotfiles-ssh,456,0; SSH_CONNECTION=old ;;
		nested-pane) PSMUX_SESSION=ssh; TMUX=/tmp/psmux-123/dotfiles-ssh,456,0; SHLVL=2 ;;
		named-other-socket) PSMUX_SESSION=ssh; TMUX=/tmp/psmux-123/default,456,0 ;;
		main-ssh-socket) PSMUX_SESSION=main; TMUX=/tmp/psmux-123/dotfiles-ssh,456,0 ;;
		missing-overlay) rm -f "$HOME/.bashrc.ssh" ;;
		bypass-env) PSMUX_SSH_AUTOATTACH=0 ;;
		bypass-file) touch "$HOME/.psmux-no-autoattach" ;;
		command) BASH_EXECUTION_STRING='printf command' ;;
		nested) SHLVL=2 ;;
		missing) PATH=/nonexistent ;;
		failure) export PSMUX_TEST_EXIT=42 ;;
	esac
	if [[ $scenario == psmux-command ]]; then BASH_EXECUTION_STRING='printf command'; fi
	case "$scenario" in
		input-pipe|psmux-input-pipe) source "$hook_path" </dev/null ;;
		output-pipe|psmux-output-pipe) source "$hook_path" > "$test_directory/output" ;;
		noninteractive|psmux-noninteractive) bash --noprofile --norc -c 'source "$1"; printf "%s\n" "$CODEX_HOME" "$GH_CONFIG_DIR" > "$PSMUX_TEST_ENVIRONMENT_LOG"' bash "$hook_path" ;;
		interactive-command|psmux-interactive-command) SHLVL=0 bash --noprofile --rcfile "$hook_path" -ic 'printf "%s\n" "$CODEX_HOME" "$GH_CONFIG_DIR" > "$PSMUX_TEST_ENVIRONMENT_LOG"' ;;
		*) source "$hook_path" ;;
	esac
	if [[ $scenario == repeat ]]; then source "$hook_path"; fi
	if [[ $scenario == psmux-reload ]]; then
		CODEX_HOME=existing
		GH_CONFIG_DIR=existing-gh
		source "$hook_path"
	fi
	PATH=$original_path
	local actual_calls
	actual_calls=$(wc -l < "$PSMUX_TEST_LOG")
	if [[ $actual_calls -ne $expected_calls ]]; then
		printf 'FAIL %s: expected %s calls, got %s\n' "$scenario" "$expected_calls" "$actual_calls" >&2
		exit 1
	fi
	if [[ $expected_calls == 1 ]] && [[ $(cat "$PSMUX_TEST_LOG") != '-L dotfiles-ssh new-session -A -s ssh' ]]; then
		printf 'FAIL %s: unexpected psmux arguments\n' "$scenario" >&2
		exit 1
	fi
	local actual_overlay
	local -a selected_environment
	actual_overlay=$(wc -l < "$PSMUX_TEST_OVERLAY_LOG")
	mapfile -t selected_environment < "$PSMUX_TEST_ENVIRONMENT_LOG"
	if [[ $actual_overlay -ne $expected_overlay ]] ||
		[[ $expected_overlay -gt 0 && ${selected_environment[0]-} != "$HOME/.codex-personal" ]] ||
		[[ $expected_overlay == 0 && $CODEX_HOME != existing ]] ||
		[[ $expected_overlay == 0 && ${selected_environment[0]-existing} != existing ]] ||
		[[ $expected_overlay -gt 0 && ${selected_environment[1]-} != "$HOME/.config/gh-ssh" ]] ||
		[[ $expected_overlay == 0 && ${selected_environment[1]-existing-gh} != existing-gh ]] ||
		[[ $expected_overlay == 0 && $GH_CONFIG_DIR != existing-gh ]]; then
		printf 'FAIL %s: unexpected SSH overlay, Codex home or GitHub config directory\n' "$scenario" >&2
		exit 1
	fi
	rm -f "$test_directory/.psmux-no-autoattach"
	printf 'PASS %s\n' "$scenario"
)

run_case attach 1 1
run_case repeat 1 2
run_case psmux-reload 0 2
run_case failure 1 1
for scenario in bypass-env bypass-file missing ssh-pane warm-pane warm-nested-pane stale-pane nested-pane psmux psmux-local psmux-custom psmux-command psmux-socket psmux-noninteractive psmux-interactive-command psmux-input-pipe psmux-output-pipe named-other-socket main-ssh-socket warm-other-socket warm-no-socket; do
	run_case "$scenario" 0 1
done
for scenario in local linux linux-psmux tmux command nested missing-overlay psmux-missing-overlay input-pipe output-pipe noninteractive interactive-command; do
	run_case "$scenario" 0 0
done
