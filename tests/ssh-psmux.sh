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
export PSMUX_TEST_CLIENT_LOG="$test_directory/client-environment"
export PSMUX_TEST_REPOSITORY_DIRECTORY="$repository_directory"
cat > "$test_directory/psmux" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PSMUX_TEST_LOG"
printf '%s\n' "${PSMUX_DATA_DIR-}" "${PSMUX_NO_WARM-}" >> "$PSMUX_TEST_CLIENT_LOG"
exit "${PSMUX_TEST_EXIT:-0}"
STUB
chmod +x "$test_directory/psmux"

# cleanup removes only the files created by this test, without recursive deletion.
cleanup() {
	rm -f "$test_directory/psmux" "$test_directory/calls" "$test_directory/.psmux-no-autoattach" "$test_directory/output" "$test_directory/.bashrc.ssh"
	rm -f "$test_directory/overlay-calls" "$test_directory/environment"
	rm -f "$test_directory/client-environment"
	rm -f "$test_directory/switch-rcfile" "$test_directory/switch-environment" "$test_directory/switch-direct"
	rmdir "$test_directory"
}
trap cleanup EXIT

# run_case checks overlay selection and observable child environments without reattachment.
run_case() (
	local scenario=$1 expected_calls=$2 expected_overlay=$3
	local HOME=$test_directory PATH="$test_directory:$original_path"
	local OSTYPE=msys SSH_CONNECTION='127.0.0.1 12345 127.0.0.1 22'
	local SHLVL=1
	local TMUX='' PSMUX_SESSION='' PSMUX_SSH_AUTOATTACH='' BASH_EXECUTION_STRING=''
	local DOCKER_SSH_MANAGED='' DOTFILES_DOCKER_SSH=''
	local __dotfiles_psmux_autoattach_attempted=
	local CODEX_HOME=existing
	local CLAUDE_CONFIG_DIR=existing-claude
	local GH_CONFIG_DIR=existing-gh
	local LOCALAPPDATA="$test_directory/localappdata"
	local PSMUX_DATA_DIR=inherited-registry PSMUX_NO_WARM=inherited-warm
	export PATH HOME SSH_CONNECTION TMUX PSMUX_SESSION CODEX_HOME CLAUDE_CONFIG_DIR GH_CONFIG_DIR
	export LOCALAPPDATA PSMUX_DATA_DIR PSMUX_NO_WARM
	cat > "$HOME/.bashrc.ssh" <<'OVERLAY'
printf 'loaded\n' >> "$PSMUX_TEST_OVERLAY_LOG"
source "$PSMUX_TEST_REPOSITORY_DIRECTORY/.bashrc.ssh"
printf '%s\n' "$CODEX_HOME" "$GH_CONFIG_DIR" "$CLAUDE_CONFIG_DIR" > "$PSMUX_TEST_ENVIRONMENT_LOG"
OVERLAY
	: > "$PSMUX_TEST_LOG"
	: > "$PSMUX_TEST_OVERLAY_LOG"
	: > "$PSMUX_TEST_ENVIRONMENT_LOG"
	: > "$PSMUX_TEST_CLIENT_LOG"
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
		bypass-env)
			# The sourced overlay reads this shell-local switch.
			# shellcheck disable=SC2034
			PSMUX_SSH_AUTOATTACH=0 ;;
		managed-bypass|managed-bypass-repeat|managed-bypass-file|managed-nested|managed-command|managed-pane)
			DOCKER_SSH_MANAGED=1; DOTFILES_DOCKER_SSH=required; PSMUX_SSH_AUTOATTACH=0
			case "$scenario" in
				managed-bypass-file) touch "$HOME/.psmux-no-autoattach" ;;
				managed-nested) SHLVL=2 ;;
				managed-command) BASH_EXECUTION_STRING='printf command' ;;
				managed-pane) PSMUX_SESSION=ssh ;;
			esac ;;
		managed-without-optin) DOCKER_SSH_MANAGED=1; PSMUX_SSH_AUTOATTACH=0 ;;
		optin-without-managed) DOTFILES_DOCKER_SSH=required; PSMUX_SSH_AUTOATTACH=0 ;;
		bypass-file) touch "$HOME/.psmux-no-autoattach" ;;
		command) BASH_EXECUTION_STRING='printf command' ;;
		nested) SHLVL=2 ;;
		missing)
			# Simulate a missing executable by intentionally changing command lookup.
			# shellcheck disable=SC2123
			PATH=/nonexistent ;;
		failure) export PSMUX_TEST_EXIT=42 ;;
		missing-localappdata) LOCALAPPDATA= ;;
	esac
	# Match the exported routing switches consumed by the overlay and its child shells.
	export DOCKER_SSH_MANAGED DOTFILES_DOCKER_SSH PSMUX_SSH_AUTOATTACH
	if [[ $scenario == psmux-command ]]; then BASH_EXECUTION_STRING='printf command'; fi
	case "$scenario" in
		input-pipe|psmux-input-pipe)
			# Exercise the runtime-selected overlay with redirected input.
			# shellcheck disable=SC1090
			source "$hook_path" </dev/null ;;
		output-pipe|psmux-output-pipe)
			# Exercise the same overlay with redirected output.
			# shellcheck disable=SC1090
			source "$hook_path" > "$test_directory/output" ;;
		noninteractive|psmux-noninteractive) bash --noprofile --norc -c 'source "$1"; printf "%s\n" "$CODEX_HOME" "$GH_CONFIG_DIR" "$CLAUDE_CONFIG_DIR" > "$PSMUX_TEST_ENVIRONMENT_LOG"' bash "$hook_path" ;;
		interactive-command|psmux-interactive-command) SHLVL=0 bash --noprofile --rcfile "$hook_path" -ic 'printf "%s\n" "$CODEX_HOME" "$GH_CONFIG_DIR" "$CLAUDE_CONFIG_DIR" > "$PSMUX_TEST_ENVIRONMENT_LOG"' ;;
		*)
			# The overlay path is derived from this test's checkout.
			# shellcheck disable=SC1090
			source "$hook_path" ;;
	esac
	# Re-source the runtime-selected overlay to test repeat attachment.
	# shellcheck disable=SC1090
	if [[ $scenario == repeat || $scenario == managed-bypass-repeat ]]; then source "$hook_path"; fi
	if [[ $scenario == psmux-reload ]]; then
		CODEX_HOME=existing
		CLAUDE_CONFIG_DIR=existing-claude
		GH_CONFIG_DIR=existing-gh
		# The overlay path is derived from this test's checkout.
		# shellcheck disable=SC1090
		source "$hook_path"
	fi
	PATH=$original_path
	local actual_calls
	actual_calls=$(wc -l < "$PSMUX_TEST_LOG")
	if [[ $actual_calls -ne $expected_calls ]]; then
		printf 'FAIL %s: expected %s calls, got %s\n' "$scenario" "$expected_calls" "$actual_calls" >&2
		exit 1
	fi
	if [[ $expected_calls == 1 ]] && [[ $(cat "$PSMUX_TEST_LOG") != '-f NUL -L dotfiles-session1 attach -t main' ]]; then
		printf 'FAIL %s: unexpected psmux arguments\n' "$scenario" >&2
		exit 1
	fi
	if [[ $PSMUX_DATA_DIR != inherited-registry || $PSMUX_NO_WARM != inherited-warm ]]; then
		printf 'FAIL %s: client routing leaked into the parent shell\n' "$scenario" >&2
		exit 1
	fi
	if [[ $expected_calls == 1 ]]; then
		local -a client_environment
		mapfile -t client_environment < "$PSMUX_TEST_CLIENT_LOG"
		if [[ ${client_environment[0]-} != "$(cygpath -w "$LOCALAPPDATA/Dotfiles/PsmuxDaily/registry")" || ${client_environment[1]-} != 1 ]]; then
			printf 'FAIL %s: unexpected daily registry or warm-server policy\n' "$scenario" >&2
			exit 1
		fi
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
		[[ $expected_overlay == 0 && $GH_CONFIG_DIR != existing-gh ]] ||
		[[ $expected_overlay -gt 0 && ${selected_environment[2]-} != "$HOME/.claude-personal" ]] ||
		[[ $expected_overlay == 0 && ${selected_environment[2]-existing-claude} != existing-claude ]] ||
		[[ $expected_overlay == 0 && $CLAUDE_CONFIG_DIR != existing-claude ]]; then
		printf 'FAIL %s: unexpected SSH overlay, Codex/Claude homes or GitHub config directory\n' "$scenario" >&2
		exit 1
	fi
	rm -f "$test_directory/.psmux-no-autoattach"
	printf 'PASS %s\n' "$scenario"
)

run_case managed-bypass 0 1
run_case managed-bypass-repeat 0 2
run_case managed-bypass-file 0 1
run_case managed-nested 0 0
run_case managed-command 0 0
run_case managed-pane 0 1
run_case managed-without-optin 0 1
run_case optin-without-managed 0 1
run_case attach 1 1
run_case repeat 1 2
run_case psmux-reload 0 2
run_case failure 1 1
run_case missing-localappdata 0 1
for scenario in bypass-env bypass-file missing ssh-pane warm-pane warm-nested-pane stale-pane nested-pane psmux psmux-local psmux-custom psmux-command psmux-socket psmux-noninteractive psmux-interactive-command psmux-input-pipe psmux-output-pipe named-other-socket main-ssh-socket warm-other-socket warm-no-socket; do
	run_case "$scenario" 0 1
done
for scenario in local linux linux-psmux tmux command nested missing-overlay psmux-missing-overlay input-pipe output-pipe noninteractive interactive-command; do
	run_case "$scenario" 0 0
done

# assert_switch_environment checks descendant records against explicit environment and SHLVL expectations.
assert_switch_environment() {
	local log_path=$1 expected_records=$2 expected_codex=$3 expected_claude=$4
	local expected_session=$5 expected_tmux=$6
	local expected_ssh_connection=$7 expected_github_directory=$8 scenario_label=$9 require_direct_level=${10}
	local -a recorded_environment
	mapfile -t recorded_environment < "$log_path"
	if [[ ${#recorded_environment[@]} -ne $((expected_records * 7)) ]]; then
		printf 'FAIL %s: unexpected descendant record count\n' "$scenario_label" >&2
		exit 1
	fi
	local record_offset
	for ((record_offset = 0; record_offset < ${#recorded_environment[@]}; record_offset += 7)); do
		if [[ ${recorded_environment[record_offset]} != "$expected_codex" ||
			${recorded_environment[record_offset + 1]} != "$expected_claude" ||
			${recorded_environment[record_offset + 2]} != "$expected_ssh_connection" ||
			${recorded_environment[record_offset + 3]} != "$expected_github_directory" ||
			${recorded_environment[record_offset + 4]} != "$expected_session" ||
			${recorded_environment[record_offset + 5]} != "$expected_tmux" ]]; then
			printf 'FAIL %s: unexpected descendant environment\n' "$scenario_label" >&2
			exit 1
		fi
		if [[ $require_direct_level == 1 && ${recorded_environment[record_offset + 6]} != 1 ]] ||
			[[ $require_direct_level != 1 && ${recorded_environment[record_offset + 6]} -le 1 ]]; then
			printf 'FAIL %s: unexpected descendant SHLVL\n' "$scenario_label" >&2
			exit 1
		fi
	done
}

# run_switch_case compares the unsafe and corrected switches across real Bash startup reloads.
run_switch_case() (
	local context=$1 ssh_mode=$2 switch_mode=$3
	local scenario="switch-$context-$ssh_mode-$switch_mode"
	local HOME=$test_directory PATH="$test_directory:$original_path" SHLVL=1
	local CODEX_HOME="$HOME/.codex-personal" CLAUDE_CONFIG_DIR="$HOME/.claude-personal"
	local GH_CONFIG_DIR="$HOME/.config/gh-ssh" SSH_CONNECTION=''
	local PSMUX_SESSION='' TMUX='' PSMUX_SSH_AUTOATTACH=''
	local DOCKER_SSH_MANAGED='' DOTFILES_DOCKER_SSH='' BASH_ENV='' ENV=''
	local PSMUX_TEST_FORCE_DIRECT=0 PSMUX_TEST_RELOAD_DEPTH=1
	local PSMUX_TEST_RCFILE="$test_directory/switch-rcfile"
	if [[ $ssh_mode == ssh ]]; then SSH_CONNECTION='127.0.0.1 12345 127.0.0.1 22'; fi
	case "$context" in
		session) PSMUX_SESSION=main ;;
		socket) TMUX=/tmp/psmux-123/default,456,0 ;;
	esac
	if [[ $switch_mode == direct-control ]]; then
		PSMUX_TEST_FORCE_DIRECT=1
		PSMUX_SSH_AUTOATTACH=0
	fi
	export HOME PATH SHLVL CODEX_HOME CLAUDE_CONFIG_DIR GH_CONFIG_DIR SSH_CONNECTION
	export PSMUX_SESSION TMUX PSMUX_SSH_AUTOATTACH DOCKER_SSH_MANAGED DOTFILES_DOCKER_SSH BASH_ENV ENV
	export PSMUX_TEST_FORCE_DIRECT PSMUX_TEST_RELOAD_DEPTH PSMUX_TEST_RCFILE
	cat > "$HOME/.bashrc.ssh" <<'OVERLAY'
source "$PSMUX_TEST_REPOSITORY_DIRECTORY/.bashrc.ssh"
OVERLAY
	cat > "$PSMUX_TEST_RCFILE" <<'RELOAD'
set -eu
# Child Bash resets OSTYPE on Linux; exercise the native Windows hook explicitly.
OSTYPE=msys
if [[ $PSMUX_TEST_FORCE_DIRECT == 1 ]]; then SHLVL=1; fi

# record_environment appends one fixed-width record without displaying credentials.
record_environment() {
	printf '%s\n' "${CODEX_HOME-<unset>}" "${CLAUDE_CONFIG_DIR-<unset>}" \
		"${SSH_CONNECTION-<unset>}" "${GH_CONFIG_DIR-<unset>}" \
		"${PSMUX_SESSION-<unset>}" "${TMUX-<unset>}" "$SHLVL" >> "$1"
}

if [[ $PSMUX_TEST_RELOAD_DEPTH == 1 ]]; then record_environment "$HOME/switch-direct"; fi
# The hook and overlay are selected from this test's checkout.
# shellcheck disable=SC1091
source "$PSMUX_TEST_REPOSITORY_DIRECTORY/.bashrc.ssh-psmux"
record_environment "$HOME/switch-environment"
if [[ $PSMUX_TEST_RELOAD_DEPTH -gt 0 ]]; then
	export PSMUX_TEST_RELOAD_DEPTH=$((PSMUX_TEST_RELOAD_DEPTH - 1))
	if [[ $- == *i* ]]; then
		bash --noprofile --rcfile "$PSMUX_TEST_RCFILE" -i
	else
		bash --noprofile --norc "$PSMUX_TEST_RCFILE"
	fi
fi
exit
RELOAD
	: > "$PSMUX_TEST_LOG"
	: > "$test_directory/switch-environment"
	: > "$test_directory/switch-direct"
	local parent_environment
	parent_environment=$(printf '%s\n' "$CODEX_HOME" "$CLAUDE_CONFIG_DIR" "$PSMUX_SESSION" "$TMUX" "$SSH_CONNECTION" "$GH_CONFIG_DIR")
	local -a switch_arguments=(-u CODEX_HOME -u CLAUDE_CONFIG_DIR)
	if [[ $switch_mode != hazard ]]; then switch_arguments+=(-u PSMUX_SESSION -u TMUX); fi
	if [[ $switch_mode == noninteractive ]]; then
		env "${switch_arguments[@]}" bash --noprofile --norc "$PSMUX_TEST_RCFILE"
	else
		# No -c: direct SSH routing must be tested without BASH_EXECUTION_STRING.
		env "${switch_arguments[@]}" bash --noprofile --rcfile "$PSMUX_TEST_RCFILE" -i
	fi
	local expected_session='<unset>' expected_tmux='<unset>'
	if [[ $switch_mode == hazard ]]; then expected_session=$PSMUX_SESSION; expected_tmux=$TMUX; fi
	# Check the direct child before the hook, then both generations after startup reloads.
	assert_switch_environment "$test_directory/switch-direct" 1 '<unset>' '<unset>' "$expected_session" "$expected_tmux" \
		"$SSH_CONNECTION" "$GH_CONFIG_DIR" "$scenario" "$PSMUX_TEST_FORCE_DIRECT"
	if [[ $switch_mode == hazard || $switch_mode == direct-control ]]; then
		assert_switch_environment "$test_directory/switch-environment" 2 "$HOME/.codex-personal" "$HOME/.claude-personal" "$expected_session" "$expected_tmux" \
			"$SSH_CONNECTION" "$GH_CONFIG_DIR" "$scenario" "$PSMUX_TEST_FORCE_DIRECT"
	else
		assert_switch_environment "$test_directory/switch-environment" 2 '<unset>' '<unset>' "$expected_session" "$expected_tmux" \
			"$SSH_CONNECTION" "$GH_CONFIG_DIR" "$scenario" "$PSMUX_TEST_FORCE_DIRECT"
	fi
	if [[ -s $PSMUX_TEST_LOG || $SHLVL != 1 || $parent_environment != "$(printf '%s\n' "$CODEX_HOME" "$CLAUDE_CONFIG_DIR" "$PSMUX_SESSION" "$TMUX" "$SSH_CONNECTION" "$GH_CONFIG_DIR")" ]]; then
		printf 'FAIL %s: psmux called or parent environment changed\n' "$scenario" >&2
		exit 1
	fi
	printf 'PASS %s\n' "$scenario"
)

for context in session socket; do
	for ssh_mode in local ssh; do
		for switch_mode in hazard switched noninteractive; do
			run_switch_case "$context" "$ssh_mode" "$switch_mode"
		done
	done
done
run_switch_case direct ssh switched
run_switch_case direct ssh direct-control
