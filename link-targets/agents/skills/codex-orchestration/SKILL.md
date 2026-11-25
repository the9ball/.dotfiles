---
name: codex-orchestration
description: For Claude Code only. Use when the user appoints Claude Code as orchestrator for an identified Issue, PR, or task and delegates implementation to Codex CLI workers through that appointment. Excludes ordinary delegation, single reviews, and tasks without an appointment.
---

# Codex orchestration

## Discovery contract

- Host fallback: exempt; Claude Code host instructions route an orchestrator appointment directly to this Skill
- Positive trigger: The user appoints Claude Code as orchestrator for an identified Issue, PR, or task to delegate implementation to Codex CLI workers.
- Negative trigger: Ordinary delegation, a single review, a task without an appointment, or execution by a host other than Claude Code.
- Conditional dependency: Apply `link-targets/agents/skills/execution-lifecycle-gate/SKILL.md` for the execution contract and gates, `link-targets/agents/skills/delegation/SKILL.md` for handoff, model selection and verification of results, and `link-targets/agents/skills/codex-invocation/SKILL.md` for CLI dispatch, resume and result handling. For external operations, apply `link-targets/agents/skills/external-operation-authorization/SKILL.md`, including the repository standing push approval when applicable. For GitHub writes, also apply `link-targets/agents/skills/github/SKILL.md` and `link-targets/agents/skills/external-posting/SKILL.md`.
- Failure mode: If the appointment, target, or authority is missing or ambiguous, stop and ask the user. Never widen the scope. If a required dependency cannot be resolved or its installed version lacks the needed operation, stop and report the blocker. This includes a missing implementation or resume form in `codex-invocation`.

## Runtime contract

Use this Guide for the duration of a valid appointment. The primary mode is ChatGPT for requirements and final checks, Claude Code as coordinator, and Codex CLI as implementation worker. Two-layer operation (ChatGPT and user-driven Codex) is the fallback for simple tasks and when Claude is unavailable.

## Guide

### Appointment and authority

- Confirm the repository, Issue/PR/task, permitted external operations (if any), and whether the user explicitly permits creating worktrees. Use the appointment's model and reasoning effort selections for the main worker and spot reviewer. Resolve each unspecified field under `delegation` by inheritance or runtime default as applicable. Preserve each explicit selection.
- The appointment authorizes delegation to Codex CLI workers for the identified task and the read-only spot reviews those workers dispatch without per-delegation confirmation. Claude Code subagents remain subject to the normal delegation rule in `CLAUDE.md`. Apply the existing scope, execution, review, Git, and external-operation contracts. PR creation, updates, and comments use the existing external authorization rules. Merge, Issue closure, permission relaxation, and new contracts require separate authorization.
- The appointment ends when the task is complete, the user stops it, or the scope changes materially. Unrelated work requires its own authority.

### Roles and worktree isolation

- Claude Code is the coordinator under `execution-lifecycle-gate`. Fix the execution contract and target identity, manage the gates, and own commits, pushes, PRs, and GitHub records within the applicable authority.
- The main Codex worker is the Implementer. It changes and verifies files within the fixed contract, with Git writes and external operations forbidden. It dispatches a read-only spot-review subagent using the settings resolved under Appointment and authority. The child does not run a second lifecycle. Any coordinator review required by `execution-lifecycle-gate` remains in force.
- Use a dedicated worktree for changes to shared instructions, Skills, or chezmoi sources so running agents remain unaffected until merge. Create one only with the user's explicit approval. Before committing in a linked worktree, check `git var GIT_AUTHOR_IDENT`. If that check fails, use the identity already resolved by the main checkout of the same repository for that commit only, and record the fallback (Issue #200). Do not write it to Git configuration. If the identity cannot be confirmed, stop before committing.

### Worker request and sessions

- In the handoff, fix the repository, task, checkout and branch, permitted files, approvals, prohibited operations (including all Git writes and network access), and stop conditions. Specify the verification commands and require each command's exact exit code. Require original line endings to be preserved and new files to follow repository conventions. Specify explicit `.\` prefixes for relative script paths in PowerShell. Follow `codex-invocation` for Windows-specific request requirements.
- Include the spot review scope and the selected model and effort. Require a report of changed files, verification commands with exit codes and key results, spot findings and their disposition, and any blockers or unverified work.
- Bundle planning, implementation, verification, and spot review into one worker call. Resume the saved session for small follow-ups on the same work, and start a fresh session for independent review. Parallelize only read-only work or writes in separate worktrees with non-overlapping files.

### Acceptance and SHA-bound review

- Inspect the actual diff for scope and line endings and run the repository's required checks yourself before push. For the9ball/.dotfiles, follow its AGENTS.md and run `pwsh -NoProfile -File scripts/check-ci.ps1` at the repository root. A worker report does not establish acceptance.
- Open the PR as Draft. Record a passing review with the full reviewed SHA in the PR, for example in a review-state table in the PR body, before marking it ready. A different PR head invalidates the pass. Before pushing a new head to a PR that is ready for review, return it to Draft under the applicable GitHub authorization and keep it there until the new head passes. If returning it to Draft is unauthorized, stop before pushing and ask for authorization. If a ready PR already has a head different from the reviewed SHA, return it to Draft when authorized or ask for authorization. Any interim commits made by Claude need a worker review before completion.

### Checkpoints and recovery

- At each milestone, record the branch, full head SHA, and next owner in the Issue or PR when authorized, using GitHub-safe information and the existing posting rules. If Issue or PR records are unauthorized, use another authorized place named in the appointment. If none is named, report each checkpoint to the user at the milestone. Keep session IDs and process details local.
- On resume, compare the checkpoint with the current branch, local and remote head, working tree, and running workers. Confirm from the checkpoint and any subsequent handoff that Claude is still the current owner. When checkpoints were reported to the user instead of recorded at an authorized destination, ask the user to confirm the current owner before continuing after any interruption. If the current owner is a user-driven Codex session in two-layer operation or anyone else besides Claude, or if ownership is uncertain, wait for the user's instruction even if the files and heads are unchanged. Stop and ask if you find a change you did not make or cannot establish the current state.
- **Worker limit exhausted.** Record the call as incomplete with its reset time (or record that the time is unknown). Keep the same account, Codex home, and route. Resume the saved session when the retry rule in `codex-invocation` allows it (after a known reset, or when the reset time is unknown and the limit is known to have reset or the user decides to retry), or, if the appointment allows interim work, implement in Claude under the SHA-bound gate and keep the PR in Draft marked as awaiting worker review. Review Claude's interim commits in a fresh worker session fixed to the new head SHA; do not resume the interrupted implementation session for that review, because its target has changed.
- **Claude limit exhausted or Claude unavailable.** Work stops at the last checkpoint. The user may switch the task to two-layer operation (ChatGPT and user-driven Codex) under the ChatGPT orchestrator guide (`chatgpt-web/guides/orchestrator.md`, which only ChatGPT reads), starting at that checkpoint. On return, apply the checkpoint reconciliation and owner check above. If another route advanced the task, wait for the user's instruction before continuing.

### Reporting and evaluation

- When authorized, record detailed discussion, decision grounds, and verification results in the Issue or PR under the existing posting rules. Report to the user for milestone checkpoints when required above, when a decision or approval is needed, when a blocker arises, or when a PR is ready for acceptance.
- After five appointed tasks or one month from adoption, whichever comes first, evaluate the mode. For each task record human interventions (count and time), Claude and Codex usage, two-layer fallbacks and their reasons, and problems found during acceptance or review.
