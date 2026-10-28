---
name: delegate-readonly-investigation
description: "[For Codex app or CLI only. Not for use by Claude Code or other agents] Coordinate bounded investigations through reusable user-visible tasks or conditional fallback candidates, using normal instruction constraints or verified strict technical RO and externally selected model and effort settings. Use when delegation protects the primary context or continues an earlier investigation. Do not use for write work or small tasks whose delegation overhead exceeds the work."
---

# Delegate Read-only Investigation

> Codex app or CLI only. Never use this skill from Claude Code or another agent product. Preserve the existing user-visible task route when its required capabilities are available. Select the mode before assessing a route; do not substitute a different model or execution route silently.

Coordinate an investigation from the primary Codex task. Keep the delegated task read-only, preserve its context across follow-ups, and return evidence to the primary task for verification and final judgment.

Resolve model and reasoning effort independently from applicable external selections, following normal instruction precedence. Pass explicitly selected fields on creation and continuation. At creation, inherit unspecified fields from the primary task when supported; otherwise omit them and use the runtime's defaults. At continuation, leave unspecified fields unchanged. This skill supplies no fixed model or effort and does not change the primary chat's settings or Advisor role/trigger rules.

## Guardrails

- Use a delegation route only when the user explicitly authorizes it in the current request or through durable instructions such as `AGENTS.md`. Candidate eligibility does not replace authorization.
- Delegate only bounded read-only search, documentation checks, codebase exploration, and evidence gathering. Keep small, clear work in the primary task when delegation overhead exceeds the work.
- Do not delegate file edits, external writes, destructive actions, approvals, purchases, or material scope expansion.
- Instruct the worker task not to create subagents or additional tasks and not to modify files or external state.
- Use the same saved local checkout as the primary task. Never create, select, move, or remove a worktree from this skill. Leave any worktree decision to the user and the primary task. If they select another checkout, use that existing selection without changing it.
- Run sequentially: while the worker task is active, make the primary task wait and do not perform separate work against the shared checkout.
- Keep integration, evidence verification, decisions, and the final response in the primary task.
- Do not claim that a particular model or effort ran unless task activity or tool output identifies the effective settings; a requested setting alone does not prove execution.

## Select the Investigation Mode

- After approved deployment of this Skill and its effective host route, `normal` is the default for already authorized investigation delegation; do not request fresh approval for each unchanged authorized investigation.
- A plain read-only investigation means behavioral read-only and uses `normal`. Native children may inherit the parent's effective permissions, including `workspace-write`; capability is not authorization to use it.
- Select `strict_technical_ro` when the user, an upper contract, or a concrete risk makes technical non-modification or isolation a requirement. If the required guarantee is ambiguous, clarify it without weakening it to normal.
- Strict requirements apply to every route, including user-visible tasks, native children, and exec. Never downgrade strict to normal because evidence or a backend is unavailable; a new approval is not technical proof.
- In normal, bans on edits, external writes, settings / authentication / privilege changes, and further delegation are instructions, not technical guarantees. Disclose inherited permissions and residual effects once at dispatch; do not repeat unchanged warnings on follow-ups.
- Normal does not guarantee technical RO: mistakes, prompt injection, startup effects, and ordinary backend logs / session persistence can remain possible. Do not convert a normal success or a read-only name into strict eligibility evidence.
- Record mode and required guarantees in the request and workstream identity. A later explicit normal choice requires a newly assessed scope and authorization, not an automatic retry or reuse of a strict handle.

## Verify Normal Eligibility

Normal preflight checks purpose, scope / authorization, prohibitions, completion conditions, and the current backend / access prospect; it does not require the strict five conditions.

1. Confirm existing authorization, the same saved checkout, a callable backend and recoverable result channel, and a reasonable prospect of access to the authorized sources.
2. Identify inherited / applicable permissions and unused capabilities without adding privileges, changing credentials or accounts, or weakening configuration. An unknown exec authority difference blocks that candidate, not an otherwise usable native child.
3. Resolve explicit model / effort selections and required continuation support under the shared rules. Unknown effective settings alone do not block normal dispatch unless the request itself requires proof of them; record unknowns and do not claim a model ran.
4. Stop for concrete unacceptable confidentiality or startup effects: unauthorized secrets or uncertain target scope, known unapproved settings / external writes, or an indeterminate necessary startup-effect boundary. Stop when new authority, connections or authentication changes are required, or policy denies execution.

Do not require prior actual-read success, a safety probe / fixture, technical write or delegation prevention, hiding every tool, or a parent-prepared all-material packet for normal dispatch. Mere presence of write tools or MCP does not reclassify or block all normal investigations.
Confirm actual reads and evidence quality from the child's results and the parent's source verification after collection; this is result validation, not a syscall audit or proof of technical RO.

## Select the Delegation Route

1. Inspect the capabilities exposed by the current runtime. If task creation, listing, messaging, reading, and waiting are available, preserve the existing task procedure below.
2. For normal, if the currently exposed API does not establish a usable task route, consider currently known native capabilities without proving global capability absence or exhaustive catalog discovery. Report only that this execution's dedicated route is unconfirmed, not that the product lacks it. For strict fallback, only verified absence of a required task capability opens candidate evaluation. A policy denial, failed attempt, timeout, or ambiguous outcome is not capability absence.
3. Provisionally evaluate a native subagent (`spawn_subagent` or the runtime's equivalent), then `codex exec`. This is an initial candidate selection, not an unconditional launch order or formal backend adoption.
4. Apply Verify Normal Eligibility for normal; require all five conditions in Verify Strict Eligibility for strict before any route launches. An unknown strict condition fails eligibility; do not select an unverified strict candidate.
5. If no candidate qualifies, report each limitation and missing evidence, and stop. Do not automatically perform the investigation in the primary task.

Do not retry a policy-denied operation through another backend. A failed or ambiguous task attempt goes to Handle Failure, not to another route.
This Skill does not authorize backend experiments, expanded permissions, or bypassing policy denials. Separate approval for a concrete bounded experiment is required when existing evidence is insufficient.
Keep the assessment provisional: Issue #145 owns formal selection, and #146 / #147 retain their unproven effective-safety findings. Static contract tests do not certify technical read-only enforcement.

## Verify Strict Eligibility

For strict only, record a separate assessment for each candidate, including user-visible tasks. Require all five conditions together:

1. **Authorized read:** evidence that the candidate actually read the authorized file content; a launch, CLI help, or promise to read does not establish success.
2. **Technical effect limits:** evidence that the investigation is technically prevented from modifying files, including files inside the checkout, or changing external state. Limit reads to authorized targets. Assess filesystem, shell, network, MCP, API, and hooks separately.
3. **No further delegation:** technical prevention of extra agents, tasks, and subprocess-based delegation, including a general shell launching another CLI.
4. **Independent execution and collection:** evidence of an independent child execution and an attributable result channel that the primary task can recover and verify.
5. **Continuity and settings:** evidence that the required continuation is supported and that requested model / effort correspond to effective settings under the common selection rules.

Prompt prohibitions, an inherited writable sandbox, or `--sandbox read-only` alone do not prove these conditions. Do not infer missing controls from a route's name or a successful exit.
Bind evidence to the backend, runtime and version, same checkout and target revision, effective authority, verification method, and any unproven parts. Past success in another environment is not current eligibility evidence.
Existing actual-read evidence from an authorized execution may qualify only after revalidating the same backend, runtime, version, checkout, target revision, and effective authority. Obtaining missing eligibility evidence requires an independently approved bounded evidence-gathering experiment; the production investigation must not gather that evidence. Any mismatch or unknown keeps the investigation stopped.
Assess backend/provider/session transport separately from investigation-tool or shell network, MCP, and API effects. Required provider transport does not grant investigation tools external-effect authority or weaken any technical gate.
Do not grant permissions, weaken a sandbox, bypass approvals, ignore rules, or use `--ignore-user-config` to remove safety configuration in order to make a candidate qualify.
If eligibility evidence is missing, keep the investigation stopped. Any separately approved evidence-gathering experiment remains an experiment, not an eligible investigation or formal safety guarantee.

## Start and Recover the Selected Backend

These shared steps apply after authorization and the selected mode's eligibility checks; strict requires all five conditions before any dispatch. A command or tool's presence alone is insufficient.
Resolve explicit model and effort selections independently before dispatch. If either selection is unsupported, stop and report it; do not substitute settings or silently drop a specified field.
For unspecified fields, retain the creation inheritance / runtime-default and continuation-preservation rules above. Record requested and effective values separately; a worker's self-report is not effective-setting proof.
Use the same saved checkout and sequential primary-task waiting rules in Guardrails. Preserve the workstream identity and self-contained request requirements below for every backend.
If continuation requirements change or a later follow-up needs unsupported continuation, stop and reassess. A new execution is not a resume; a new workstream needs authorization and mode-specific eligibility before launch, and must not become an automatic failed-route retry.

### Native subagent candidate

- In normal, use the available child API and disclose inherited authority; prefer a fresh context with a self-contained request. For strict, verify actual child tool, sandbox, and authority controls. Parent inheritance does not establish a narrower child boundary; prompt-only edit / delegation bans are insufficient for strict.
- Create the child using applicable explicit model / effort fields and supported inheritance for unspecified fields. Retain the returned child handle, backend, parent / engagement identity, mode, target revision, and permission / eligibility assessment.
- Send continuation requests only to that exact verified handle, use its supported wait / result facilities, and collect attributable evidence. A title or an unrelated child is not an identity match.
- In strict, if child-specific technical controls, required continuation, or effective settings cannot be verified, do not select or launch this investigation candidate. Normal uses its own preflight, not this strict proof requirement.

### Non-interactive CLI candidate

- Check the installed CLI's supported non-interactive, structured-output, and explicit-session continuation interface without treating help output as safety proof. Do not prescribe unverified flags or invent a command that broadens authority.
- Fix the invocation, working directory, authorized investigation roots, applicable authority and mode-specific controls, and bounded output location before launch. Do not implicitly use a wrapper, another environment, account, or credentials. A separate process does not imply the parent's permissions or settings.
- Start an eligible independent execution with structured events and separate process exit status. Retain the actual session ID, invocation identity, backend version, requested / effective settings evidence, and result references.
- If continuation is required, verify persistence and resume support before selection. An ephemeral invocation cannot satisfy required resume.
- Resume only the exact recorded session ID; never use `--last`. Revalidate the session, backend, checkout, target revision, authority, settings, mode, and governing assumptions before continuing.
- A changed target or epoch invalidates automatic reuse. Stop and reassess rather than resuming against a different checkout or carrying old eligibility evidence into a changed environment.

### Collect and classify

- Wait for the selected execution; do not investigate in parallel against the shared checkout. Collect the requested evidence and independently inspect cited sources in the primary task.
- Distinguish complete evidence, policy refusal, execution failure, interruption, partial output, and an unknown outcome. Exit 0 or `turn.completed` alone does not establish evidence acquisition.
- Report the selected backend, verification basis, effective permissions, collection method, requested / effective settings, and all unproven parts. Do not invent a final result from partial events or missing output.
- When identity, result status, or effects are ambiguous, stop and preserve the uncertainty; do not launch another backend or automatically retransmit the operation.
- Contract changes and static tests alone do not establish strict eligibility or successful evidence acquisition. Confirm actual independent execution and verifiable result collection without treating static validation as a runtime safety guarantee.

## Decide Whether to Reuse

Treat these fields as the delegated workstream identity:

- objective and expected deliverable;
- relevant artifacts and investigation scope;
- project, selected checkout, and branch;
- authorization and read-only boundary;
- mode and required guarantees;
- governing assumptions.

Reuse the same worker task when those fields remain materially the same. Continue it for follow-up research, corrections, clarification, stronger evidence, and validation of the same conclusion. Apply any applicable explicit model or effort selection on continuation, and leave unspecified fields unchanged.
Mode changes invalidate automatic reuse; reassess authorization and the new mode's conditions without carrying over unproven strict eligibility.

Create a new worker task when any identity field changes materially, prior assumptions become obsolete, or stale context is visibly impairing quality or efficiency. Use observed degradation rather than turn count alone. Examples include repeatedly relying on superseded assumptions, confusing distinct artifacts, or requiring the core constraints to be restated. Do not split solely because work enters a new phase. Prefer a concise handoff of confirmed facts and open questions over copying the full transcript.

## Find an Existing Delegated Task

This section and the following task creation / continuation sections apply to the existing user-visible task backend, not to fallback handle discovery.

1. Prefer a previously retained `threadId` and `hostId` from the current primary task.
2. If those identifiers are unavailable, list recent tasks and examine candidates with the title prefix `Subagent: [調査]`; after verifying those candidates, also inspect the legacy title prefixes `Subagent: [Sol調査]`, `Subagent: [Luna調査]`, and `[Luna調査]` when no verified reusable candidate remains among the new-prefix candidates.
3. Read each plausible candidate and verify its initial delegation marker and workstream identity before reusing it. Accept the legacy marker `Delegated role: Luna read-only investigator` only for a matching investigation, and apply the explicit worker settings on continuation.
4. Never reuse a task based on title alone, and never reuse an unrelated user-created task.

## Create the Worker Task

1. List available projects and select the project matching the primary task.
2. Use that project's saved local environment so the worker reads the same checkout as the primary task. Do not request a new worktree.
3. Create a task with title `Subagent: [調査] <short workstream>`. Pass applicable explicit model and reasoning effort selections through `model` and `thinking`; for unspecified fields, use supported inheritance from the primary task, or omit those fields when inheritance is unavailable. Report an unsupported explicit selection instead of silently substituting settings.
4. If creation still returns only a `clientThreadId`, do not pass it to tools requiring a `threadId`. Resolve the ready task through the recent-task list and verify its delegation marker before continuing.
5. Retain the ready task's `threadId` and `hostId` for follow-ups.

For every backend, make the initial prompt self-contained with four required parts:

1. Purpose: objective, relevant context, mode and required guarantees; include marker `Delegated role: read-only investigator` and applicable model / effort selections with their sources.
2. Scope / authorization: repository, approved roots, in-scope and out-of-scope artifacts, known entrypoints or Issue references. The parent need not determine every source or command in advance.
3. Prohibitions: no edits, external writes, settings / authentication / privilege changes, further delegation or authority expansion. Stop and report if more scope or authority is needed; leave approvals to the user.
4. Completion: acceptance criteria, exact validation and expected return distinguishing verified facts, inference and unknowns, with source locations, necessary command results, missing evidence and escalation conditions.

The child independently searches, reads and gathers evidence within the authorized scope. Do not require the parent to collect all source material or feed every answer source through stdin in normal; separate review-packet contracts retain their own requirements.

Require concise findings that distinguish verified facts from inference and include exact file references or source links, relevant commands or queries, uncertainty, and the cheapest next check when evidence is incomplete.

## Continue and Collect Results

1. Wait for the delegated task rather than repeatedly polling it or doing other work against the shared checkout.
2. Read its final result and inspect the cited evidence from the primary task when practical.
3. If evidence is incomplete or a correction is needed, send a follow-up to the same task, preserving its conversation context. Pass applicable explicit model/effort selections through `model` and `thinking`, and leave unspecified fields unchanged.
4. State only the delta, new evidence, challenged conclusion, and required output in the follow-up.
5. Wait again and repeat while the workstream identity remains stable.
6. If the delegated task requests user approval or expanded authority, leave that decision to the user; do not answer on the user's behalf.

Keep an active delegated task unarchived while meaningful follow-up is likely. Archive it only when the user asks or another explicit lifecycle policy authorizes archival.

## Handle Failure

If any selected backend fails during creation or continuation, report the exact error and affected step, acquired evidence, missing evidence, and uncertain effects. Do not silently substitute another model, reasoning effort, backend, or primary-task execution. Route selection is initial only; failure, denial or ambiguity never opens another backend or a normal downgrade. Do not automatically retry with other permissions or credentials. A timeout does not establish that execution stopped or never started; inspect the retained handle / PID before any resubmission. Offer the smallest viable next check within existing authority, or request the missing bounded approval.
