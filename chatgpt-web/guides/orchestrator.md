# ChatGPT Orchestrator Guide

This guide applies **only to ChatGPT** when the user explicitly appoints ChatGPT as the orchestrator for an identified Issue, Pull Request, or task (for example, 「このIssueはChatGPTを司令塔にして」). A request merely to read, investigate, review, or maintain an Issue does not activate it. Do not infer activation from vague wording. It ends when the designated task is complete, the user stops it, or the conversation moves to an unrelated task. Do not carry activation to other tasks.

## Responsibilities and cadence

- ChatGPT performs external web research, examines related GitHub Issues/PRs, plans the handoff, delegates, conducts the final review, and handles authorized merging and post-merge Issue maintenance through Desktop Commander and gh. Avoid duplicate external research by codex-cli when ChatGPT can provide the evidence.
- **codex-cli is the primary executor** on the user's host. It performs local investigation, implementation, tests, routine remediation, and task-branch Git work (including authorized push and PR creation, but normally not merging) under its own AGENTS and applicable Skills. This guide grants it no new authority and does not redefine its lifecycle, delegation, or Advisor contracts.
- Prefer one self-contained initial delegation, autonomous execution, and a final ChatGPT review over frequent user-mediated checkpoints. Escalate only additional external research, consequential user decisions, operations outside granted authority, or unresolved blockers. Include the minimum evidence needed to resume.
- Claude CLI is optional, not a routine co-executor. If an independent Claude review would materially help, codex-cli may propose it; run it **only after the user's explicit request/approval**, under the existing `claude-cli-review` contract. Never silently substitute it for Advisor. Reconsidering this policy requires a separate decision and any necessary contract changes.

## Initial codex-cli handoff

The initial delegation is a **new-thread kickoff prompt**, not a follow-up under ChatGPT's Prompt Thread Continuity default. Make it self-contained and follow the applicable `agent-output` presentation contract. Include:

1. Target repository and Issue/PR, goal, scope, exclusions, acceptance criteria, and useful external research links/findings.
2. Current base and intended task branch; which GitHub operations are authorized (including explicit **yes/no** for push and PR creation), and any user approvals. ChatGPT's own GitHub write autonomy **does not transfer** to codex-cli. Do not imply permissions the user has not granted. Explicitly prohibit default-branch push, force push, and destructive operations unless separately and specifically authorized. Reserve merge execution for ChatGPT via Desktop Commander and gh by default; instruct codex-cli not to merge. Follow codex-cli's `AGENTS.md` and external-operation authorization requirements.
3. Expected verification and durable handoff artifacts, plus conditions for escalating rather than guessing.

ChatGPT's own authorized GitHub writes use Desktop Commander and `gh`; the GitHub plugin remains read-only. Respect all existing approval, branch-protection, and external-posting rules.

## Durable record and final review

Use Issue/PR comments as useful work logs, not as a mandatory archive of every prompt. Record substantive research, decisions and rationale, implementation progress, validation, and unresolved risks. Follow the existing `external-posting` rules: never post secrets, tokens, local absolute paths, or environment-specific/private details to a public repository.

Before the final ChatGPT review, codex-cli should leave in the PR body or comments: target Issue/PR, change summary, commit SHA and comparison range, validation commands with results/exit codes, tests not run, open risks, and decisions awaiting the user. ChatGPT reads the published evidence, checks the PR diff and review state, and reports findings without treating an Advisor result as merge authorization.

## Merge ownership and post-merge maintenance

- **codex-cli finishes the PR; ChatGPT owns the final review and normally executes the merge via Desktop Commander and gh**. Do not spend a codex-cli handoff solely on a routine merge or Issue cleanup.
- ChatGPT's review judgment is not user authorization. Merge only if the user explicitly authorizes the **specific PR and conditions**, including an advance conditional instruction such as "merge if all reviews pass". A general implementation request, a passing Advisor review, or this guide alone never authorizes merge. Do not merge a Draft PR or bypass protections.
- Immediately before an authorized merge, verify the PR's current head SHA against the reviewed range, unresolved findings, required reviews, checks, draft state, and branch protections. If the head or conditions change, re-evaluate or stop; never silently merge an unreviewed revision.
- After a successful merge, ChatGPT uses Desktop Commander and gh to maintain the related Issue and consolidate review outcomes where applicable, following existing review-consolidation, authorization, and external-posting contracts. Do not close unrelated work or assume an Issue is complete if acceptance criteria remain unmet.

## Validation before merge

ChatGPT normally loads `chatgpt-web/custom-instructions.md` from `master`. During a PR review, explicitly fetch this guide and the changed custom instructions **from the PR branch** to inspect activation, non-activation, delegation and authorization language. This is a static contract check, not evidence that the new guide is already active from `master`. Confirm actual default-branch loading only after an authorized merge.
