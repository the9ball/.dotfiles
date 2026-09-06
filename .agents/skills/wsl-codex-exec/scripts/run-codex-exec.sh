#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${HOME:-}" ]]; then
    echo 'WSL HOME is not set.' >&2
    exit 1
fi

if [[ "$#" -eq 0 ]]; then
    echo 'Usage: run-codex-exec.sh [codex exec options] <prompt-or->' >&2
    exit 64
fi

repository_directory="${HOME}/.dotfiles"
aqua_config_path="${repository_directory}/aqua.yaml"
aqua_bin_directory="${HOME}/.local/share/aquaproj-aqua/bin"
codex_home_directory="${HOME}/.codex-wsl"
codex_executable="${aqua_bin_directory}/codex"

if [[ ! -d "${repository_directory}" ]]; then
    echo "WSL dotfiles directory was not found: ${repository_directory}" >&2
    exit 1
fi

if [[ ! -f "${aqua_config_path}" ]]; then
    echo "Aqua configuration was not found: ${aqua_config_path}" >&2
    exit 1
fi

if [[ ! -d "${codex_home_directory}" ]]; then
    echo "WSL Codex home was not found: ${codex_home_directory}" >&2
    echo 'Complete codex-wsl/CODEX_HOME.md before using this skill.' >&2
    exit 1
fi

if [[ ! -x "${codex_executable}" ]]; then
    echo "Aqua-managed Codex executable was not found: ${codex_executable}" >&2
    echo 'Install the declared Codex package in WSL before using this skill.' >&2
    exit 1
fi

# Keep the ordinary one-shot CLI on Aqua's lifecycle. Remote Control uses the
# separate standalone launcher under codex-wsl/start-codex-wsl.sh.
export AQUA_GLOBAL_CONFIG="${aqua_config_path}"
export PATH="${aqua_bin_directory}:${PATH:-}"
export CODEX_HOME="${codex_home_directory}"

cd "${repository_directory}"
exec "${codex_executable}" exec "$@"
