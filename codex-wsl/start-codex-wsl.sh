#!/usr/bin/env bash
set -euo pipefail

# Keep the Remote Control CLI configuration native to WSL. The Windows Codex
# configuration contains Windows-only paths that the Linux binary cannot parse.
export AQUA_GLOBAL_CONFIG="${HOME}/.dotfiles/aqua.yaml"
export PATH="${HOME}/.local/share/aquaproj-aqua/bin:${PATH}"
export CODEX_HOME="${HOME}/.codex-remote"

# Remote Control is owned by the standalone installation in CODEX_HOME. The
# regular `codex` command is Aqua-managed and has a separate update lifecycle.
codex_standalone="${CODEX_HOME}/packages/standalone/current/codex"
if [[ ! -x "${codex_standalone}" ]]; then
    echo "Remote Control standalone executable was not found: ${codex_standalone}" >&2
    echo "Complete codex-wsl/CODEX_HOME.md before registering the Windows task." >&2
    exit 1
fi

exec "${codex_standalone}" remote-control start
