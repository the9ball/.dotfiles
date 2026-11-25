#!/bin/bash
# Exercise PR gitleaks ranges against commit graphs in a temporary repository.
set -euo pipefail

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT

# Keep inherited repository variables and Git configuration out of the fixture.
git_local_variables=$(git rev-parse --local-env-vars)
while IFS= read -r git_variable; do
    unset "$git_variable"
done <<< "$git_local_variables"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME='Range Test' GIT_AUTHOR_EMAIL='range@example.invalid'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
cd -- "$temporary_directory"
git init --quiet --object-format=sha1 --template= .
tree_sha=$(git mktree < /dev/null)

# Create a commit with the supplied message and optional -p arguments.
make_commit() {
    local message=$1
    shift
    git commit-tree "$tree_sha" -m "$message" "$@"
}

# Assert the exit code and exact stdout, including the newline on success.
assert_range() {
    local name=$1 expected_status=$2 expected_range=$3
    local status=0
    shift 3
    bash "$script_directory/ci-gitleaks-range.sh" pull_request "$@" > stdout 2> stderr || status=$?
    if [[ $status -ne $expected_status ]]; then
        printf '%s: expected exit %s, got %s\n' "$name" "$expected_status" "$status" >&2
        cat stderr >&2
        exit 1
    fi
    if [[ $expected_status -eq 0 ]]; then
        if ! printf '%s\n' "$expected_range" | cmp -s - stdout; then
            printf '%s: expected range %s, got %s\n' "$name" "$expected_range" "$(cat stdout)" >&2
            exit 1
        fi
    elif [[ -s stdout ]]; then
        printf '%s: a failed check printed a range\n' "$name" >&2
        exit 1
    fi
}

event_base=$(make_commit 'Event base')
original_head=$(make_commit 'Original PR head' -p "$event_base")
original_merge=$(make_commit 'Original PR merge' -p "$event_base" -p "$original_head")
git checkout --quiet --detach "$original_merge"
assert_range 'unchanged base' 0 "$event_base..$original_head" "$event_base" "$original_head" "$original_merge"

# The shared commit advances the merge base, then base and PR head diverge.
shared_commit=$(make_commit 'Shared after event base' -p "$event_base")
current_base=$(make_commit 'Current base' -p "$shared_commit")
current_head=$(make_commit 'Current PR head' -p "$shared_commit")
current_merge=$(make_commit 'Current PR merge' -p "$current_base" -p "$current_head")
git checkout --quiet --detach "$current_merge"
assert_range 'advanced base' 0 "$shared_commit..$current_head" "$event_base" "$current_head" "$current_merge"
assert_range 'wrong second parent' 1 '' "$event_base" "$original_head" "$current_merge"
assert_range 'merge SHA differs from HEAD' 1 '' "$event_base" "$original_head" "$original_merge"

unrelated_base=$(make_commit 'Unrelated event base')
assert_range 'unrelated event base' 1 '' "$unrelated_base" "$current_head" "$current_merge"
git checkout --quiet --detach "$original_merge"
assert_range 'rewound first parent' 1 '' "$current_base" "$original_head" "$original_merge"

octopus_merge=$(make_commit 'Octopus merge' -p "$current_base" -p "$current_head" -p "$original_head")
git checkout --quiet --detach "$octopus_merge"
assert_range 'octopus merge' 1 '' "$event_base" "$current_head" "$octopus_merge"
git checkout --quiet --detach "$current_head"
assert_range 'non-merge' 1 '' "$event_base" "$current_head" "$current_head"

disjoint_merge=$(make_commit 'Disjoint merge' -p "$current_base" -p "$unrelated_base")
git checkout --quiet --detach "$disjoint_merge"
assert_range 'no merge base' 1 '' "$event_base" "$unrelated_base" "$disjoint_merge"

# Independent merges of the two branches leave both branch tips as merge bases.
left_merge=$(make_commit 'Left merge' -p "$current_base" -p "$current_head")
right_merge=$(make_commit 'Right merge' -p "$current_head" -p "$current_base")
ambiguous_merge=$(make_commit 'Ambiguous merge' -p "$left_merge" -p "$right_merge")
git checkout --quiet --detach "$ambiguous_merge"
assert_range 'multiple merge bases' 1 '' "$event_base" "$right_merge" "$ambiguous_merge"
