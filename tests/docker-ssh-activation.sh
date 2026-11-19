#!/usr/bin/env bash
# Exercise activation guards with inert metadata commands; never start Docker or PowerShell.
set -eu

repository_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1090
source "$repository_directory/docker-ssh/chezmoi/AppData/Local/Dotfiles/DockerSsh/docker-ssh.bash"

# Return the requested fixture path without requiring Windows path conversion.
cygpath() {
    printf '%s\n' "${@: -1}"
}

# Count metadata requests without invoking PowerShell, credentials, or a deployment.
pwsh.exe() {
    metadata_calls=$((metadata_calls + 1))
}

# Reject an attributed selection field before metadata calls or partial activation.
check_rejected_attribute() (
    local selection_name=$1 selection_attribute=$2 before_declaration
    local metadata_calls=0 activation_reference=original
    unset DOCKER_SSH_DEPLOYMENT _docker_ssh_active _docker_ssh_function_definition
    case "$selection_attribute" in
        integer) declare -gi "$selection_name=9" ;;
        indexed) declare -ga "$selection_name=([0]=original)" ;;
        associative) declare -gA "$selection_name=([fixture]=original)" ;;
        nameref) declare -gn "$selection_name=activation_reference" ;;
        readonly) declare -gr "$selection_name=original" ;;
        *) return 1 ;;
    esac
    before_declaration=$(declare -p "$selection_name")
    if docker-ssh-activate /fixture/deployment >/dev/null 2>&1; then
        printf 'FAIL accepted %s %s\n' "$selection_name" "$selection_attribute" >&2
        return 1
    fi
    [[ $(declare -p "$selection_name") == "$before_declaration" ]] || return 1
    [[ $activation_reference == original && $metadata_calls == 0 ]] || return 1
    ! declare -F docker >/dev/null || return 1
    printf 'PASS rejected %s %s without state changes\n' "$selection_name" "$selection_attribute"
)

# Preserve normal and exported scalar activation, repeated selection, and deactivation.
check_scalar_activation() (
    local scalar_attribute=$1 metadata_calls=0
    unset DOCKER_SSH_DEPLOYMENT _docker_ssh_active _docker_ssh_function_definition
    if [[ $scalar_attribute == exported ]]; then
        export DOCKER_SSH_DEPLOYMENT=original _docker_ssh_active='' _docker_ssh_function_definition=''
    fi
    docker-ssh-activate /fixture/deployment || return 1
    [[ $DOCKER_SSH_DEPLOYMENT == /fixture/deployment && $_docker_ssh_active == 1 ]] || return 1
    [[ $(declare -f docker) == "$_docker_ssh_function_definition" && $metadata_calls == 1 ]] || return 1
    docker-ssh-activate /fixture/deployment || return 1
    [[ $metadata_calls == 1 ]] || return 1
    docker-ssh-deactivate || return 1
    ! declare -F docker >/dev/null || return 1
    [[ ! ${DOCKER_SSH_DEPLOYMENT+x} && ! ${_docker_ssh_active+x} && ! ${_docker_ssh_function_definition+x} ]] || return 1
    printf 'PASS scalar %s activation lifecycle\n' "$scalar_attribute"
)

for selection_name in DOCKER_SSH_DEPLOYMENT _docker_ssh_active _docker_ssh_function_definition; do
    for selection_attribute in integer indexed associative nameref readonly; do
        if ! check_rejected_attribute "$selection_name" "$selection_attribute"; then
            printf 'FAIL rejection %s %s\n' "$selection_name" "$selection_attribute" >&2
            exit 1
        fi
    done
done
check_scalar_activation ordinary
check_scalar_activation exported
