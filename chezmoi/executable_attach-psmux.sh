#!/usr/bin/env bash
# Attach this terminal to the daily Session 1 psmux session; only the desktop monitor creates it.
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

if [[ -z ${LOCALAPPDATA-} ]]; then
    printf '%s\n' 'LOCALAPPDATA is unavailable.' >&2
    exit 1
fi

PSMUX_DATA_DIR=$(cygpath -w "$LOCALAPPDATA/Dotfiles/PsmuxDaily/registry")
export PSMUX_DATA_DIR
export PSMUX_NO_WARM=1

# Ignore client config: psmux can bootstrap new-session from it even for attach.
command psmux -f NUL -L dotfiles-session1 attach -t main
