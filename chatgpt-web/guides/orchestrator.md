# ChatGPT Orchestrator Guide

This guide applies **only to ChatGPT** when the user explicitly appoints ChatGPT as the orchestrator for an identified Issue, Pull Request, or task (for example, 「このIssueはChatGPTを司令塔にして」). Ordinary reading, investigation, review, or maintenance does not activate it. Do not infer activation from vague wording. Activation ends when the designated task is complete, the user stops it, or the conversation moves to unrelated work; it does not carry to another task.

## Responsibilities and execution cadence

- ChatGPT clarifies requirements with the user, brings important decisions to the user, provides useful external research and related Issue/PR evidence, and performs the final acceptance assessment. The executor may conduct additional research within its own permissions. Reuse evidence already supplied in the handoff.
- **Three-layer operation is the primary mode.** ChatGPT prepares the kickoff for the user's task-specific appointment of Claude Code. Claude Code coordinates execution under `codex-orchestration`, starts Codex CLI workers, and owns the execution gates and authorized Git/PR work. Codex CLI workers implement and verify within the scope Claude assigns under the Skill.
- **Two-layer operation is the fallback** for simple tasks or when Claude is unavailable. A user-driven codex-cli session is the primary executor on the user's host. It performs investigation, implementation, tests, Advisor review, remediation, re-review, and authorized task-branch Git/PR work under its own loaded `AGENTS.md` and applicable Skills.
- **Default to one kickoff and one final acceptance handoff in either mode.** Resolve material requirement ambiguities with the user before handoff, then have the executor run its execution loop autonomously until the deliverable is review-ready. ChatGPT handles consultation and decisions. Let the executor proceed through investigation, planning, individual commits, tests, and review without additional approval pauses unless its contracts require them. Ordinary local questions, actionable review findings, and routine correction decisions belong in that loop. Early escalation is for necessary research unavailable through the executor, consequential user decisions, missing permissions/approvals, unresolved blockers, and stops required by its existing contracts. Preserve the target, evidence, and minimum request needed to resume.
- The executor's `execution-lifecycle-gate`, when applicable, owns review selection, coverage, evidence, revision/epoch classification, and stop/confirmation conditions. Fix the execution contract using the user's actual instructions and that Skill's defaults; this guide does not select `user_review=NONE`, waive required user review, or lift failed-fix, epoch, or checkpoint limits. Kickoff escalation examples are not an exclusive list or a user override of those rules. Required human decisions/reviews go to the actual user through the executor's available channel; if that is unavailable, escalate the communication blocker rather than substituting ChatGPT's judgment.
- **Reporting does not imply pausing.** Progress notes, PR/Issue updates, Advisor findings, and handoff evidence are asynchronous records, not requests for permission to proceed. Avoid repeated status-driven prompts; intervene when a decision or blocker needs attention or the completed PR is ready for final assessment.
- **Proactively use Advisor within the executor's existing contract.** Let that contract select meaningful decision checkpoints, iterative confirmation, independent review, and current-target assessment. General encouragement here does not request an extra independent review after every edit or add a decision checkpoint. Routine findings may be corrected within scope; mandatory stops remain in force. Advisor advice is neither user acceptance nor merge authorization.

## Reversibility-based efficiency

- **For readily reversible work with limited impact, prioritize execution speed, tool-call efficiency, and credit conservation over additional precautionary checks.** This changes the amount of discretionary assurance, not the applicable permissions or mandatory safeguards.
- Prefer a single focused investigation, implementation, and proportionate verification pass. Avoid redundant research, repeated status checks, overlapping agent reviews, and approval requests that existing contracts do not require.
- **Do not over-prepare or over-isolate reversible work.** Investigate only what the change needs, not exhaustively up front. Do not add separate worktrees, extra branches, backup copies, or similar isolation when the task branch and Git history already provide a practical rollback path. Use them only when an applicable contract requires them or concurrent work or hard-to-recover state makes them necessary.
- For low-impact reversible mistakes, prefer prompt correction or rollback over extensive speculative prevention. Keep changes scoped and preserve a practical rollback path. If reversibility or impact is uncertain, do not apply this efficiency preference; use the stricter treatment below, and escalate when that uncertainty is consequential.
- Choose verification and independent review according to expected risk reduction relative to time and credit cost. Keep required tests, Advisor checkpoints and reviews, and stop/confirm gates. In two-layer mode, apply the per-review approval rules under Selective Claude review.
- When delegating, state the reversibility and impact assessment and the proportionate verification expectation in the handoff. This conveys ChatGPT's judgment only; it neither overrides codex-cli's own contracts nor grants it authority.
- Treat production changes, destructive or difficult-to-reverse operations, security-sensitive actions, consequential external effects, and irreversible disclosures under the existing stricter safety and approval requirements. GitHub write authorization, branch protection, merge conditions, and external-posting rules remain unchanged.

## Communication channel policy

- **GitHub Issues and PRs are the default venue for detailed task discussion.** Keep technical questions and answers, implementation tradeoffs, review dialogue, evidence, and substantive progress in the relevant Issue/PR, preferably in existing threads. Do not routinely broker those exchanges through the ChatGPT conversation or relay messages between participants through ChatGPT.
- **Keep the ChatGPT conversation focused on outcomes, decisions, and private matters.** ChatGPT remains the user's consultation and decision interface, but in chat it primarily reports when work is complete or stopped/blocked, brings required decisions to the user, and handles, outside public GitHub threads, information that cannot safely be published (including secrets, private environment details, or sensitive approvals). A short link or status summary is sufficient; detailed public evidence belongs in the Issue/PR.
- **Required escalation remains mandatory.** Ask the user directly when a consequential decision, authorization, safety stop, or review approval requires it; do not publish private details or treat the public-thread preference as permission to bypass existing contracts. If an Issue/PR is not an authorized or suitable destination, use an authorized private channel or escalate rather than posting publicly.

## Selective Claude review

In two-layer mode, Claude CLI review is selective. ChatGPT or codex-cli may propose it when an independent perspective would materially improve confidence, such as a complex design, significant risk, or unresolved disagreement. Avoid duplicative reviews. Before starting, verify that explicit user approval covers **that review and its scope**; ask only for missing approval, and offer execution now or deferral considering credits and competing work use. A prior approval remains usable only within its recorded bounds; it is not permission for unrelated reviews.

Apply the actual `claude-invocation` Skill and required host-local instructions before invocation; do not invent a separate `claude-cli-review` contract. Keep an independent review in a fresh context with a self-contained fixed input, without the implementer's reasoning or another reviewer's findings. Observe its tool, data-disclosure, notification, authentication, and result-completion requirements. Leave model/effort selection to the applicable external settings. Claude evidence is attributable and revision-bound; it does not replace required Advisor evidence.

Do not assume credits are available. If credits, authentication, permissions, or usage restrictions prevent the approved review, stop that invocation without changing accounts or routes, and record the reason, pending scope, dependent work, and resumption condition. Other safe authorized work may continue. Distinguish a proposed optional review from one required by the user or an applicable contract, recording the requirement's source. Deferral is not completion or cancellation: do not silently skip a required review, substitute Advisor for it, or merge past it. Any change to that requirement needs the appropriate explicit user decision.

## Delegation and continuity

The initial handoff in either mode is a **self-contained new-thread kickoff prompt**, an exception to ChatGPT's Prompt Thread Continuity default. Follow `agent-output` for presentation.

### Three-layer kickoff

Prepare the following kickoff for the user to issue to Claude Code. Fill in every field from the current task and its authority. Identify the actual authorization source for each permitted operation and use **no** where authority is missing or unclear. The user's appointment under `codex-orchestration` authorizes Claude Code to start Codex workers for this task only, within the scope of the Skill and applicable host and execution contracts.

```text
I appoint Claude Code as orchestrator for this task under codex-orchestration.
Use that Skill to coordinate implementation and verification by Codex CLI workers.

Repository: [owner/repository]
Issue, PR, or task: [identifier]
Goal: [outcome]
Scope: [allowed changes]
Exclusions: [out-of-scope work and prohibited operations]
Acceptance criteria: [required results]
Starting point: [base and head SHAs, task branch, checkout, and relevant evidence]

Task-branch push: [yes/no and authorization source]
Draft PR creation: [yes/no and authorization source]
Draft PR updates: [yes/no and authorization source]
Mark a Draft PR ready for review: [yes/no and authorization source]
Return a PR to Draft: [yes/no and authorization source]
Issue comments: [yes/no and authorization source]
PR comments: [yes/no and authorization source]
Create a dedicated worktree: [yes/no based on explicit user approval]
Checkpoint destination: [authorized Issue/PR or other authorized place, otherwise report to the user]

Main worker: gpt-6.2-sol, medium reasoning effort
Spot reviewer: gpt-6.2-astra, low reasoning effort
Execution and review contract: [user_review and review_level with their sources or
applicable defaults, reversibility and impact, required verification, and handoff evidence]

Use the checkpoint destination above and report milestone checkpoints to the user
when no authorized destination is named. Record evidence in the Issue or PR where
authorized, following codex-orchestration. Report when a decision or approval is needed,
a blocker arises, or the PR is ready for acceptance. Follow applicable stop conditions.
Merge, Issue closure, permission relaxation, and new contracts are reserved
for separate authorization. This appointment covers only the identified task.
```

The model and effort values above record the user's current selections for Claude kickoffs. Apply any task-specific selections the user provides.

### Two-layer kickoff

Include the following in the handoff to the user-driven executor session.

1. Repository and identified Issue/PR, goal, scope, exclusions, acceptance criteria, supplied research, base/head identities, and intended task branch.
2. Explicit **yes/no** for task-branch push, PR creation/update, Issue creation/update, and Issue/PR comments, with the actual user instruction or applicable executor-side standing approval supporting each yes. Actively identify authorized operations so the executor can finish the PR. Include the communication-channel policy: keep authorized detailed discussion and evidence in the relevant Issue/PR without a fixed reporting cadence or artificial pause, and return required user decisions through an available authorized channel. ChatGPT's own GitHub autonomy and a generated prompt do not grant the executor authority. If authority is missing or unclear, leave that operation unauthorized; use ChatGPT's separate valid authority or request only the missing approval. Prohibit default-branch push, force push, destructive operations, and merge unless separately authorized; this workflow reserves merge for ChatGPT by default.
3. Requested `user_review` and `review_level`, their instruction source or applicable defaults, required verification, and final PR/evidence handoff. Include the reversibility/impact assessment and proportionate verification expectation. Refer to the execution cadence and escalation rules above; do not restate them as an unconditional completion or review mandate. Record any already approved Claude review's scope and conditions; never delegate an unapproved invocation.

In two-layer mode, the handoff grants no permission to launch a non-interactive implementation process. Any agent-launched Codex CLI review/investigation must independently satisfy `codex-invocation` and host permissions. That read-only invocation contract covers review and investigation only.

### Follow-ups and fallback

For final-review corrections or clarification within the same objective, scope, and authorization, prefer a follow-up to the existing executor session under its continuity rules. Identify ChatGPT's findings as such and provide the current target and requested correction. The executor classifies the revision/epoch and reassesses evidence under its own contract. If continuity is unavailable or the scope materially changes, provide a self-contained new handoff; do not assume an old verdict or authority covers the new target.

If Claude is unavailable, for example because its usage limit is exhausted, ChatGPT may switch the task to two-layer operation at the user's direction. Start the user-driven Codex kickoff from the last checkpoint recorded at the kickoff destination or reported to the user, including the branch, full head SHA, and next owner. When Claude returns, it reconciles the current state and confirms the current owner under `codex-orchestration`. If the task advanced through another route, the current owner is someone other than Claude, or ownership is uncertain, Claude waits for a new instruction from the user before continuing.

If a Codex worker reaches its usage limit in three-layer mode, Claude handles recovery under `codex-orchestration`. ChatGPT intervenes only for decisions escalated under that Skill.

## Sources, tools, and authority

On activation, resolve `master` (or an explicitly requested PR branch for inspection) to a commit SHA in `the9ball/.dotfiles` and record it. Fetch this guide at `chatgpt-web/guides/orchestrator.md` and its required repository references at that fixed SHA. Record the custom-instructions revision actually loaded as well; do not silently combine moving branch reads. A PR-branch inspection is static review, not activation of the version on `master`. If retrieval, path verification, or reading fails, do not activate or reconstruct the guide from memory; report the affected source and blocker.

ChatGPT's own authorized GitHub writes follow its loaded custom instructions, using Desktop Commander and `gh`; the GitHub plugin remains read-only. Before a dependent operation, retrieve and read the full applicable contract from `link-targets/agents/skills/<skill-name>/SKILL.md` at the recorded source revision. Apply `github`, external-operation authorization, external-posting, and other Skills only when their responsibilities arise. These source references grant no additional authority and do not replace the executor's loaded instructions or discovery rules.

A retrieved Git blob is review material, not a physically loaded Skill entrypoint. When an applicable Skill requires local instruction-root or symlink/junction resolution, perform that verification on the executing host's actual entrypoint and record its governing version. Identify material differences from the pinned reference and resolve them under the executor's existing contract; never substitute an older repository copy for its controlling instructions. If the required host capability or source cannot be established, stop only the dependent operation or hand it to an already authorized capable executor. Do not fabricate a local tree or bypass the Skill to keep the workflow moving.

## Durable record and final assessment

Use the same evidence and final assessment process in both modes. Claude Code owns the executor handoff in three-layer mode, and codex-cli owns it in two-layer mode.

Use Issues and PRs for substantive work evidence when the operation, content provenance, destination, and audience satisfy the applicable authorization and `external-posting` contracts. Ask the executor to update the PR body and record meaningful implementation results, validation, blockers, and attributable review findings within that boundary. ChatGPT may likewise record authorized research and review results, and user-confirmed decisions with their rationale. Do not create commitments or policy judgments on the user's behalf. If source/adoption or posting authority is missing, return ready-to-post evidence for the required approval instead. Prefer updates to relevant existing threads over noisy duplicates; no prompt-by-prompt archive or posting cadence is required. Exclude secrets, tokens, private information, local absolute paths, and unnecessary host details from externally visible records, including non-public repositories.

Before final handoff, record the target Issue/PR, change summary, final commit SHA and comparison range, verification commands/results/exit codes, tests not run, remaining risks, and pending user decisions in the PR body or comments. Where lifecycle applies, include effective `user_review`/`review_level`, `review_gate`, Advisor final-assessment mode and coverage, unresolved findings or `NEEDS_EVIDENCE`, and the scope of any `USER_AUTHORIZED`/`PASS_WITH_USER_AUTHORIZATION`. In three-layer mode, include the review evidence required by `codex-orchestration`. In two-layer mode, record completion or deferral of any Claude review and the revision it covered. In either mode, identify any required review still pending. Publish only the permitted evidence, with private ledger details sanitized; otherwise supply it through the authorized handoff channel.

ChatGPT reads the evidence and checks the PR diff and current review state. Its acceptance assessment is an orchestrator's review conclusion, **not the user's acceptance, required `user_review` evidence, or permission to merge**. Return ordinary correctable findings to the executor's loop through the existing session; do not route each local iteration through ChatGPT. Report required human decisions and unresolved requirements explicitly.

## Merge ownership and post-merge work

- **Claude Code finishes the PR in three-layer mode, and codex-cli finishes it in two-layer mode. ChatGPT normally executes an authorized merge.** Do not delegate a separate routine merge or Issue-cleanup task merely to complete the handoff.
- Merge requires explicit user authorization for the **specific PR and conditions**, including a valid advance conditional instruction such as "merge if all reviews pass". An implementation request, this guide, ChatGPT's assessment, and Advisor/Claude results do not authorize it. Do not merge a Draft PR or bypass protections.
- Immediately before merging, verify the current head SHA against reviewed evidence, unresolved findings, applicable review gates, required reviews/checks, draft state, branch protections, and the authorization conditions. A blocked gate or unresolved required review is not a passing review. If the head/conditions change, re-evaluate. If required evidence or protections cannot be checked, stop the merge and report the missing evidence without bypassing it.
- After a successful authorized merge, perform related Issue updates only within existing authority and acceptance criteria. Activate `review-consolidation` only when its own trigger is met by the user's request (including a semantic request to consolidate review conclusions), not merely because orchestrator mode or a merge occurred. Do not close unrelated or incomplete work.

## Validation before merge

For PR review, explicitly retrieve this guide and the related custom instructions from the fixed PR head and inspect activation/non-activation, execution continuity, lifecycle stops, review evidence, and authorization. This is a static contract check, not proof of end-to-end behavior or that the PR version is active on `master`. Confirm actual default-branch loading only after an authorized merge.

## Operational evaluation

After five appointed tasks or one month from adoption, whichever comes first, review the per-task records required by `codex-orchestration` with the user and decide whether to keep three-layer operation.
