---
name: codex-orchestration
description: For Claude Code only. Use when the Decision Maker (the user) appoints Claude Code as Coordinator for an identified Issue, PR, or task and delegates implementation to Workers (Codex CLI) through that appointment. Excludes ordinary delegation, single reviews, and tasks without an appointment.
---

# Codex orchestration

The Decision Maker (the user) works with the Orchestrator (ChatGPT), the Coordinator (Claude Code), and Workers (Codex CLI). Under `execution-lifecycle-gate`, the Coordinator acts as coordinator and the Worker as Implementer. Advisor stays Advisor.

## Discovery contract

- Host fallback: exempt; Claude Code host instructions route a Coordinator appointment directly to this Skill
- Positive trigger: The Decision Maker appoints Claude Code as Coordinator for an identified Issue, PR, or task to delegate implementation to Codex CLI Workers.
- Negative trigger: Ordinary delegation, a single review, a task without an appointment, or execution by a host other than Claude Code.
- Conditional dependency: Apply `link-targets/agents/skills/execution-lifecycle-gate/SKILL.md` for the execution contract and gates, `link-targets/agents/skills/delegation/SKILL.md` for handoff, model selection and verification of results, and `link-targets/agents/skills/codex-invocation/SKILL.md` for CLI dispatch, resume and result handling. For external operations, apply `link-targets/agents/skills/external-operation-authorization/SKILL.md`, including the repository standing push approval when applicable. For GitHub writes, also apply `link-targets/agents/skills/github/SKILL.md` and `link-targets/agents/skills/external-posting/SKILL.md`.
- Failure mode: If the appointment, target, or authority is missing or ambiguous, stop and ask the Decision Maker. Never widen the scope. If a required dependency cannot be resolved or its installed version lacks the needed operation, stop and report the blocker. This includes a missing implementation or resume form in `codex-invocation`.

## Runtime contract

Use this Guide for the duration of a valid appointment. In three-layer operation, the Orchestrator handles requirements and final checks, the Coordinator coordinates execution, and Workers implement and verify. Two-layer operation uses the Orchestrator and user-driven Codex for simple tasks, when Claude is unavailable, or when the Decision Maker chooses it.

## Guide

### Appointment and authority

An explicit appointment of Claude Code 'as orchestrator' made before this wording change stays valid for its task.

- Confirm the repository, Issue/PR/task, permitted external operations (if any), and whether the Decision Maker explicitly permits creating worktrees. Use the appointment's model and reasoning effort selections for the main Worker and spot reviewer. Resolve each unspecified field under `delegation` by inheritance or runtime default as applicable. Preserve each explicit selection.
- The appointment authorizes delegation to Codex CLI Workers for the identified task and the read-only spot reviews those Workers dispatch without per-delegation confirmation. Claude Code subagents remain subject to the normal delegation rule in `CLAUDE.md`. Apply the existing scope, execution, review, Git, and external-operation contracts. PR creation, updates, and comments use the existing external authorization rules. Merge, Issue closure, permission relaxation, and new contracts require separate authorization.
- The appointment ends when the task is complete, the Decision Maker stops it, or the scope changes materially. Unrelated work requires its own authority.

### Roles and worktree isolation

- As Coordinator, fix the execution contract and target identity, manage the gates, and own commits, pushes, PRs, and GitHub records within the applicable authority.
- The main Worker changes and verifies files within the fixed contract, with Git writes and external operations forbidden. It dispatches a read-only spot-review subagent using the settings resolved under Appointment and authority. The child does not run a second lifecycle. Any Coordinator review required by `execution-lifecycle-gate` remains in force.
- Use a dedicated worktree for changes to shared instructions, Skills, or chezmoi sources so running agents remain unaffected until merge. Create one only with the Decision Maker's explicit approval. Before committing in a linked worktree, check `git var GIT_AUTHOR_IDENT`. If that check fails, use the identity already resolved by the main checkout of the same repository for that commit only, and record the fallback (Issue #200). Do not write it to Git configuration. If the identity cannot be confirmed, stop before committing.

### Worker request and sessions

- In the handoff, fix the repository, task, checkout and branch, permitted files, approvals, prohibited operations (including all Git writes and network access), and stop conditions. Specify the verification commands and require each command's exact exit code. Require original line endings to be preserved and new files to follow repository conventions. Specify explicit `.\` prefixes for relative script paths in PowerShell. Follow `codex-invocation` for Windows-specific request requirements.
- Include the spot review scope and the selected model and effort. Require a report of changed files, verification commands with exit codes and key results, spot findings and their disposition, and any blockers or unverified work.
- Bundle planning, implementation, verification, and spot review into one Worker call. Resume the saved session for small follow-ups on the same work, and start a fresh session for independent review. Parallelize only read-only work or writes in separate worktrees with non-overlapping files.

### Acceptance and SHA-bound review

- Inspect the actual diff for scope and line endings and run the repository's required checks yourself before push. For the9ball/.dotfiles, follow its AGENTS.md and run `pwsh -NoProfile -File scripts/check-ci.ps1` at the repository root. A Worker report does not establish acceptance.
- Worker and spot reviews are inputs to the Coordinator's gate, not the gate itself. The gate passes only when the completion conditions of `execution-lifecycle-gate` hold for the current SHA, including required verification, any selected user review, and, when Advisor review is `REQUIRED` (for example for changes to Skills, `AGENTS.md`, or agent definitions that affect approval or delegation), its final assessment. No review result replaces the Coordinator's acceptance, the Decision Maker's production-adoption decision under `agent-pipeline-guardrails`, or the separate authorization to merge.
- Open the PR as Draft. Record the passing gate result with the full SHA it covers in the PR, for example in a review-state table in the PR body, before marking it ready. A different PR head invalidates the pass. Before pushing a new head to a PR that is ready for review, return it to Draft under the applicable GitHub authorization and keep it there until the new head passes. If returning it to Draft is unauthorized, stop before pushing and ask for authorization. If a ready PR already has a head different from the reviewed SHA, return it to Draft when authorized or ask for authorization. Any interim commits made by the Coordinator need a Worker review before completion.

### Checkpoints and recovery

- At each milestone, record the branch, full head SHA, and next owner in the Issue or PR when authorized, using GitHub-safe information and the existing posting rules. If Issue or PR records are unauthorized, use another authorized place named in the appointment. If none is named, report each checkpoint to the Decision Maker at the milestone. Keep session IDs and process details local.
- The checkpoint records the current owner: `Claude`, `handover in progress`, or `two-layer: user-driven Codex`. Only an explicit decision of the Decision Maker to switch or return ownership changes it; ordinary checkpoint updates never overwrite it. The owner value says who may act; recording it and every operation after a switch still need their existing authorization. If no destination was authorized for writing from the start, the current owner is the Decision Maker's explicit decision, confirmed directly. If an existing destination becomes unusable, stop the switch until it is confirmed that the old route cannot resume from that record.
- On resume, compare the checkpoint with the current branch, local and remote head, working tree, and running Workers; stop and ask the Decision Maker if you find a change you did not make or cannot establish the current state. Also on resume, and immediately before starting or resuming a Worker or writing to the working tree, Git, or the task's external records, read the current owner. If it is not `Claude`, cannot be read, or is uncertain, start nothing, write nothing, and wait for the Decision Maker. With no destination, obtain the Decision Maker's answer for that resume before the first such action; a missing, earlier, or unclear answer means wait.
- To switch to two-layer operation:
  1. Record `handover in progress` (with a destination, confirm the record can be read back before continuing; without one, the Decision Maker's explicit decision is the state).
  2. Confirm that every Claude Code session for the task has ended, including any that read the owner earlier or could resume from older instructions or an earlier answer, and that every Worker, child, or pending process it started that could write has ended.
  3. Reconcile the checkout's branch, full HEAD SHA, and staged, unstaged, and untracked changes against the last checkpoint; fix how each difference is carried over, and leave to the Decision Maker any difference that needs a decision.
  4. Only then record `two-layer: user-driven Codex` (confirming the read-back when there is a destination) and hand over the reconciled state for the two-layer kickoff.

  If step 2 or 3 cannot be completed, the owner stays `handover in progress` and the Decision Maker decides.
- When the Decision Maker explicitly returns the task to Claude, keep or set `handover in progress`, cancel a two-layer kickoff that has not run, and if a two-layer session started, confirm that it and every process that could write have ended. Reconcile as in step 3, then record `Claude`. This also applies when a switch stopped midway.
- **Worker limit exhausted.** Record the call as incomplete with its reset time (or record that the time is unknown). Keep the same account, Codex home, and route. Resume the saved session when the retry rule in `codex-invocation` allows it (after a known reset, or when the reset time is unknown and the limit is known to have reset or the Decision Maker decides to retry), or, if the appointment allows interim work, implement in Claude Code under the SHA-bound gate and keep the PR in Draft marked as awaiting Worker review. Review the Coordinator's interim commits in a fresh Worker session fixed to the new head SHA; do not resume the interrupted implementation session for that review, because its target has changed.
- **Claude limit exhausted or Claude unavailable.** Coordination stops when Claude becomes unavailable. Changes made after the last checkpoint may remain, and processes Claude started may keep writing. The Decision Maker may switch the task to two-layer operation with the switching steps above.

### Reporting and evaluation

- When authorized, record detailed discussion, decision grounds, and verification results in the Issue or PR under the existing posting rules. Report to the Decision Maker for milestone checkpoints when required above, when a decision or approval is needed, when a blocker arises, or when a PR is ready for acceptance.
- After five appointed tasks or one month from adoption, whichever comes first, evaluate the mode. For each task record human interventions (count and time), Claude and Codex usage, two-layer fallbacks and their reasons, and problems found during acceptance or review.
