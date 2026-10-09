---
name: git-operations
description: Used to get Git status, fix differences/review range, handle index.lock, permission errors, and range control. It does not substitute for approval of destructive operations or push.
---

# Git operations workflow

## Discovery contract

- Host fallback: required

- Positive trigger: Handles Git status, index/ref, differential range, permission errors, lock, formatter/lint range control.
- Negative trigger: This is normal text/code work that does not deal with Git state or scope.
- Conditional dependency: Maintain the responsibility boundary between the common policy kernel and the commit-message Skill, and resolve only the dependencies that are needed.
- Failure mode: If Git identity, scope, permissions, or dependency contracts cannot be determined, do not guess; stop fail-safe.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

Resolve the loaded Skill's final existing symlink/junction entity and apply the canonical instruction-root procedure in `link-targets/agents/guides/README.md` (Reference path). Fail closed on missing, ambiguous, broken, or escaping locations; never infer the instruction root from the work root or CWD. Fix the work root and Git target from the request and current Git state, independently of the instruction root.

## Guide

A detailed guide to read before getting into Git state acquisition, modification, recovery, fixing differences and review ranges.
It supplements the responsibilities of `link-targets/agents/AGENTS.md`, root `AGENTS.md`, and `link-targets/agents/skills/commit-message/SKILL.md`, and does not define the commit message format.

### State acquisition and index.lock

- For commands whose sole purpose is to view the repository status, specify `git --no-optional-locks` before subcommands whenever possible.
- Do not specify `--no-optional-locks` for commands that can update the index, working tree, references, or history.
- If a `index.lock` error occurs, identify the target using the path displayed in the error or `git rev-parse --git-path index.lock`.
- If there is a Git process operating on the same repository or worktree, wait for it to finish before trying again.
- Do not delete the lock file or stop the process without the user's explicit approval, even if read-only checks confirm the cause and that the lock is residual from a process that has exited.

### Permission error

- If the cause is considered to be access denial, lack of authentication/authorization, sandbox restrictions, etc., obtain confirmation by indicating the required operation, target, and reason.
- Do not silently switch to a browser, another CLI/API, another account, or another save location, except for read-only operations to check the cause.
- If you cannot create or update `index.lock` in the Git management area and the same command results in a privilege error, you can elevate the privileges of that same Git command and re-execute it.
- In an environment where you know in advance that you cannot write to the Git management area with normal privileges, you can elevate the privileges of the Git command that updates the index from the beginning. However, priority should be given to checking the higher level policy.
- Presence of locks, separate Git processes, and residual locks are not treated as insufficient privileges. Deleting locks, changing credentials, and switching to another route are not included in this exception.

### Fixed difference/review range

- Before the actual review, the comparison criteria, terminal state, target identity, inclusion status, and exclusion status are uniquely fixed. Do not determine the reference and termination at the same time using only `HEAD`.
- If a PR or URL is specified, target committed differences that match the provider's fixed base/head SHA and the difference definition (usually from `merge-base(base, head)` to head). Reproduce the same merge-base difference from a fixed base/head SHA only if the provider's difference definition cannot be obtained. Don't implicitly mix moving local bases, indexes, working trees, and untracked.
- `staged` is an index based on `HEAD`, and `直近commit` (latest commit) is `HEAD^..HEAD`. `未commit` (uncommitted) or `作業ツリー` (working tree) includes staged and unstaged changes and non-ignored untracked files based on `HEAD`; ignored files are always excluded.
- Unless specified otherwise, `upstreamとの差分` (difference with upstream) is the committed change (merge-base standard) from the current branch's upstream `@{u}` to `HEAD`. Don't equate `@{u}` with PR base or release branch, and check separately whether to include dirty changes.
- The identity includes the base/target SHA of commit/PR, the index snapshot of staged, the index/tracking file snapshot of the work tree, and the path/hash manifest of target untracked.
- If the comparison criteria or endpoint is not unique, such as when the request is just 「レビューして」 ("review"), check the branch, tracking destination, PR base/head, `HEAD`, and dirty status as read-only, and suggest candidates with one question in principle. Don't use main, develop, or release branches as implicit comparison sources; do not start the review or dispatch until the user confirms the review scope.
- If `@{u}` cannot be resolved, there is a mismatch between PR head and local `HEAD`, or there is a change in the target, reconfirm the scope without making assumptions or mixing old and new evidence.
- At the beginning of the review results, describe the comparison criteria, terminating ref/SHA or snapshot identity, inclusion status, exclusion status, and handling of untracked.

### Git range control

- If a formatter, lint, or Git operation generates a large amount of out-of-scope changes, do not automatically include them; separate them, or stop and seek confirmation.
- Destructive operations, history rewrites, force pushes, and lock deletions will not be performed unless the explicit authorization boundary of `link-targets/agents/AGENTS.md` is met.

<!-- reference-kind: policy-precedence; target: link-targets/agents/AGENTS.md -->
