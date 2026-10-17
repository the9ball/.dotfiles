# Source this opt-in file, then activate one explicit deployment; no profile or Docker environment is written.
_docker_ssh_script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

# Run a standard Docker command against the validated dedicated deployment in a child-only environment.
docker-ssh() (
    [[ -n ${DOCKER_SSH_DEPLOYMENT:-} && $# -gt 0 ]] || { printf '%s\n' 'Activate an explicit TPM Docker deployment first.' >&2; return 1; }
    local metadata reader deployment argument
    reader=$(cygpath -am -- "$_docker_ssh_script_directory/Get-TpmDockerEnvironment.ps1") || return
    deployment=$(cygpath -am -- "$DOCKER_SSH_DEPLOYMENT") || return
    metadata=$(pwsh.exe -NoProfile -File "$reader" -DeploymentRoot "$deployment") || return
    local -a fields
    mapfile -t fields <<< "$metadata"
    [[ ${#fields[@]} == 5 && $metadata != *$'\r'* ]] || return 1
    [[ $1 != -* ]] || { printf '%s\n' 'Specify a Docker command; routing is fixed by this deployment.' >&2; return 1; }
    for argument in "$@"; do
        case "$argument" in
            --host|--host=*|--context|--context=*|--config|--config=*|-H|-H?*|-c|-c?*)
                printf '%s\n' 'Docker routing overrides are not accepted.' >&2; return 1 ;;
        esac
        if [[ $argument =~ ^-[^-].{1,}$ ]]; then
            printf '%s\n' 'Clustered or joined short options are not accepted; separate each option and value.' >&2; return 1
        fi
    done
    local executable binary
    executable=$(cygpath -u -- "${fields[0]}") || return
    binary=$(cygpath -u -- "${fields[1]}") || return
    unset DOCKER_HOST DOCKER_CONTEXT DOCKER_AUTH_CONFIG
    export DOCKER_CONFIG="${fields[2]}" DOCKER_SSH_HELPER_ROOT="${fields[3]}"
    export PATH="$binary:$PATH"
    export MSYS2_ENV_CONV_EXCL="${MSYS2_ENV_CONV_EXCL:+$MSYS2_ENV_CONV_EXCL;}DOCKER_CONFIG;DOCKER_SSH_HELPER_ROOT"
    export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}--host="
    "$executable" "--host=${fields[4]}" --config "${fields[2]}" "$@"
)

# Validate first, then opt this shell into ordinary docker syntax without replacing an existing alias or function.
docker-ssh-activate() {
    [[ $# == 1 ]] || return 1
    if [[ ${_docker_ssh_active:-} == 1 ]]; then
        [[ $DOCKER_SSH_DEPLOYMENT == "$1" && $(declare -f docker) == "$_docker_ssh_function_definition" ]] && return 0
        printf '%s\n' 'Deactivate before selecting another deployment.' >&2; return 1
    fi
    if alias docker >/dev/null 2>&1 || declare -F docker >/dev/null; then
        printf '%s\n' 'Existing docker alias/function preserved; activation refused.' >&2; return 1
    fi
    local reader deployment
    reader=$(cygpath -am -- "$_docker_ssh_script_directory/Get-TpmDockerEnvironment.ps1") || return
    deployment=$(cygpath -am -- "$1") || return
    pwsh.exe -NoProfile -File "$reader" -DeploymentRoot "$deployment" >/dev/null || return
    DOCKER_SSH_DEPLOYMENT=$1
    _docker_ssh_active=1
    # Delegate ordinary Docker syntax while leaving all environment overrides in the subshell above.
    docker() { docker-ssh "$@"; }
    _docker_ssh_function_definition=$(declare -f docker)
}

# Remove only this activation's function and public selection; external docker.exe remains unchanged.
docker-ssh-deactivate() {
    [[ ${_docker_ssh_active:-} == 1 ]] || return 0
    [[ $(declare -f docker) == "$_docker_ssh_function_definition" ]] || { printf '%s\n' 'Changed docker function preserved; deactivation refused.' >&2; return 1; }
    unset -f docker
    unset _docker_ssh_active _docker_ssh_function_definition DOCKER_SSH_DEPLOYMENT
}
