#!/bin/bash
# Print the gitleaks commit range for a pull_request or push event.
# Usage: bash scripts/ci-gitleaks-range.sh EVENT BASE_SHA HEAD_SHA [PR_MERGE_SHA]
# Requires complete local history and full commit SHAs; never fetches or substitutes
# a comparison base. Invalid, missing, ambiguous, or unrelated history fails closed.
set -euo pipefail

event_name=${1:?An event name is required}
comparison_base_sha=${2:?A comparison base SHA is required}
scan_head_sha=${3:?A scan head SHA is required}
scan_commits=("$comparison_base_sha" "$scan_head_sha")
if [[ "$event_name" == pull_request ]]; then
    pr_merge_sha=${4:?A PR merge SHA is required}
    scan_commits+=("$pr_merge_sha")
fi

# Restrict revisions to object IDs so Git cannot interpret options or expressions.
for commit_sha in "${scan_commits[@]}"; do
    if [[ ! "$commit_sha" =~ ^[0-9a-fA-F]{40}$ || "$commit_sha" =~ ^0+$ ]]; then
        printf 'A nonzero full commit SHA is required: %s\n' "$commit_sha" >&2
        exit 1
    fi
    git rev-parse --verify "${commit_sha}^{commit}" > /dev/null
done

if [[ $(git rev-parse --is-shallow-repository) != false ]]; then
    printf 'Complete history is required to determine the scan range.\n' >&2
    exit 1
fi

case "$event_name" in
    pull_request)
        if [[ $(git rev-parse --verify HEAD) != "$pr_merge_sha" ]]; then
            printf 'The PR merge SHA must match checkout HEAD.\n' >&2
            exit 1
        fi
        # Exact parent-list equality also rejects non-merges and octopus merges.
        merge_parents=$(git show --no-patch --format=%P "$pr_merge_sha")
        if [[ "$merge_parents" != "$comparison_base_sha $scan_head_sha" ]]; then
            printf 'The PR merge parents must match the event base and head.\n' >&2
            exit 1
        fi
        # Multiple merge bases do not identify the single required starting point.
        merge_base_sha=$(git merge-base --all "$comparison_base_sha" "$scan_head_sha")
        if [[ ! "$merge_base_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
            printf 'The PR must have exactly one merge base.\n' >&2
            exit 1
        fi
        comparison_base_sha=$merge_base_sha
        ;;
    push)
        # master forbids force-push; unrelated history must not become a fallback.
        git merge-base --is-ancestor "$comparison_base_sha" "$scan_head_sha"
        ;;
    *)
        printf 'Unsupported event: %s\n' "$event_name" >&2
        exit 1
        ;;
esac

commit_range="${comparison_base_sha}..${scan_head_sha}"
# Force Git to traverse the range before emitting it for the scanner.
git rev-list "$commit_range" > /dev/null
printf '%s\n' "$commit_range"
