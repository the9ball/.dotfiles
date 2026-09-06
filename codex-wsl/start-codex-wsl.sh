#!/usr/bin/env bash
set -euo pipefail

# Keep the Remote Control CLI configuration native to WSL. The Windows Codex
# configuration contains Windows-only paths that the Linux binary cannot parse.
export AQUA_GLOBAL_CONFIG="${HOME}/.dotfiles/aqua.yaml"
export PATH="${HOME}/.local/share/aquaproj-aqua/bin:${PATH}"
export CODEX_HOME="${HOME}/.codex-remote"
exec codex remote-control start
