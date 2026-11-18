#!/usr/bin/env bash
# Attach this terminal to the persistent SSH session, creating it when necessary.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
    printf '%s\n' 'Run this command with bash; do not source it.' >&2
    return 1
fi

set -eu

if ! command -v psmux >/dev/null 2>&1; then
    printf '%s\n' 'psmux is not available on PATH.' >&2
    exit 127
fi

if [[ ! -t 0 || ! -t 1 ]]; then
    printf '%s\n' 'Run this command from an interactive terminal.' >&2
    exit 1
fi

command psmux -L dotfiles-ssh new-session -A -s ssh
