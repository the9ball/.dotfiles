#!/bin/sh
# Validate the filenames selected by prek; never execute the checked scripts.
set -eu

check_kind=$1
shift

case "$check_kind" in
    shellcheck-bash) exec shellcheck -s bash "$@" ;;
    shellcheck-sh) exec shellcheck -s sh "$@" ;;
    bash-syntax|sh-syntax)
        # In Git Bash, /bin belongs to Git for Windows, independent of Windows PATH.
        # This avoids System32/bash.exe (the WSL launcher) even if it precedes Git.
        case "$check_kind" in
            bash-syntax) shell_executable=/bin/bash ;;
            sh-syntax) shell_executable=/bin/sh ;;
        esac
        for file_path do
            "$shell_executable" -n "$file_path" || exit "$?"
        done
        ;;
    json|yaml|toml)
        for file_path do
            case "$check_kind" in
                json) jq empty "$file_path" > /dev/null || exit "$?" ;;
                yaml) yq -p yaml '.' "$file_path" > /dev/null || exit "$?" ;;
                toml) yq -p toml '.' "$file_path" > /dev/null || exit "$?" ;;
            esac
        done
        ;;
    *) printf 'Unknown check: %s\n' "$check_kind" >&2; exit 2 ;;
esac
