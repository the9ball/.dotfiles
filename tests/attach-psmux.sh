#!/usr/bin/env bash
# Run in a real terminal: bash --noprofile --norc -i tests/attach-psmux.sh.
set -eu

if [[ ! -t 0 || ! -t 1 ]]; then
    printf '%s\n' 'Run this regression in a terminal.' >&2
    exit 1
fi

repository_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manual_command="$repository_directory/chezmoi/executable_attach-psmux.sh"
bash_executable=/bin/bash
test_directory=$(mktemp -d)
mkdir "$test_directory/empty"
export PSMUX_MANUAL_LOG="$test_directory/calls"
export PSMUX_MANUAL_SESSION="$test_directory/session"
export PSMUX_MANUAL_EVENT="$test_directory/event"
export PSMUX_MANUAL_EXIT=0
export BASH_ENV=/dev/null

# Remove only this fixture's known files and directories, without touching real psmux state.
cleanup() {
    rm -f "$test_directory/psmux" "$test_directory/calls" "$test_directory/session" "$test_directory/event" "$test_directory/output" "$test_directory/error"
    rmdir "$test_directory/empty" "$test_directory"
}
trap cleanup EXIT

cat > "$test_directory/psmux" <<'STUB'
#!/usr/bin/env bash
set -eu
[[ $# == 6 && $* == '-L dotfiles-ssh new-session -A -s ssh' ]] || exit 91
printf '%s\n' "$*" >> "$PSMUX_MANUAL_LOG"
if [[ $PSMUX_MANUAL_EXIT != 0 ]]; then exit "$PSMUX_MANUAL_EXIT"; fi
if [[ -f $PSMUX_MANUAL_SESSION ]]; then
    printf ATTACHED > "$PSMUX_MANUAL_EVENT"
else
    : > "$PSMUX_MANUAL_SESSION"
    printf CREATED > "$PSMUX_MANUAL_EVENT"
fi
STUB
chmod +x "$test_directory/psmux"
export PATH="$test_directory:$PATH"

# Require a fixture condition and report only its case name.
check() {
    if [[ $2 != "$3" ]]; then printf 'FAIL %s\n' "$1" >&2; exit 1; fi
    printf 'PASS %s\n' "$1"
}

: > "$PSMUX_MANUAL_SESSION"
parent_identity=$BASHPID
"$bash_executable" --noprofile --norc "$manual_command"
check existing-session-attached "$(cat "$PSMUX_MANUAL_EVENT")" ATTACHED
check caller-shell-not-replaced "$BASHPID" "$parent_identity"
check fixed-namespace-session-no-destructive-options "$(cat "$PSMUX_MANUAL_LOG")" '-L dotfiles-ssh new-session -A -s ssh'
rm "$PSMUX_MANUAL_SESSION"
"$bash_executable" --noprofile --norc "$manual_command"
check absent-session-created "$(cat "$PSMUX_MANUAL_EVENT")" CREATED
[[ -f $PSMUX_MANUAL_SESSION ]]

PSMUX_SSH_AUTOATTACH=0 "$bash_executable" --noprofile --norc "$manual_command"
check manual-command-independent-of-autoattach-switch "$(cat "$PSMUX_MANUAL_EVENT")" ATTACHED

export PSMUX_MANUAL_EXIT=47
if "$bash_executable" --noprofile --norc "$manual_command"; then status=0; else status=$?; fi
check psmux-failure-exit-propagated "$status" 47
export PSMUX_MANUAL_EXIT=0
: > "$PSMUX_MANUAL_LOG"
if "$bash_executable" --noprofile --norc "$manual_command" </dev/null 2>"$test_directory/error"; then status=0; else status=$?; fi
check redirected-input-refused "$status" 1
check redirected-input-does-not-call-psmux "$(wc -c < "$PSMUX_MANUAL_LOG" | tr -d '[:space:]')" 0
if "$bash_executable" --noprofile --norc "$manual_command" >"$test_directory/output" 2>"$test_directory/error"; then status=0; else status=$?; fi
check redirected-output-refused "$status" 1
check redirected-output-does-not-call-psmux "$(wc -c < "$PSMUX_MANUAL_LOG" | tr -d '[:space:]')" 0
if PATH="$test_directory/empty" "$bash_executable" --noprofile --norc "$manual_command" 2>"$test_directory/error"; then status=0; else status=$?; fi
check missing-psmux-refused "$status" 127

options_before=$-
# Exercise rejection in this shell, where an accidental exec or option mutation would destroy the test.
# shellcheck disable=SC1090
if source "$manual_command" 2>"$test_directory/error"; then status=0; else status=$?; fi
check sourced-command-refused "$status" 1
check source-does-not-change-shell-options "$-" "$options_before"
check source-does-not-replace-caller "$BASHPID" "$parent_identity"
check source-does-not-call-psmux "$(wc -c < "$PSMUX_MANUAL_LOG" | tr -d '[:space:]')" 0
