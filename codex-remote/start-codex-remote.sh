#!/usr/bin/env bash
set -euo pipefail

export CODEX_HOME=/mnt/c/Users/syasui/.codex-personal
exec codex remote-control start
