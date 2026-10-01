---
name: delegation
description: Used to handle subagent dispatch, reuse, handoff, evidence child, and session identity. Select model-specific supplementary materials only when necessary.
---

# Delegation workflow

## Discovery contract

- Positive trigger: Requires dispatch, reuse, handoff, evidence child, role, session or epoch identity decisions.
- Negative trigger: This skill does not apply to short, self-contained tasks that do not involve delegation or session identity.
- Conditional dependency: Resolve, under the necessary conditions, only the model guide that corresponds to the selected delegate model.
- Failure mode: If the required model guide or dependency contract cannot be resolved, the system stops in a fail-safe manner without relying on guesswork.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

Before execution, resolve the loaded Skill's symlink / junction to the entity path, find `link-targets/agents/reference-map.json` from its ancestors, and fix the instruction root from `repository_root` in JSON. If map is not found, cannot be interpreted as a structure, or cannot be resolved to, stop in a fail-safe manner without guessing the work root. The work root and Git target are fixed separately from the request.

## Guide

A detailed guide to read before dispatching or reusing subagents.
Supplements `link-targets/agents/AGENTS.md`'s common contract and owns delegation, handoff, and session identity details.

### Delegation decision

- If subagents can be used, delegate them unless the cost of handover, integration, and verification exceeds the effectiveness of the work.
- Handle short, self-contained tasks, tasks that require frequent user judgment, and tasks whose child-context transfer would be at least as large as the task itself in the root context.
- Do not delegate if the child cannot reach the necessary files, tools, authentication, or execution environment, cannot safely pass on confidential information, or cannot proceed independently.
- The unique workflow of a specific skill such as `zero-base-rewrite` will not be redefined in the common delegation rules, and the contract of the relevant skill will take precedence.
- When using `zero-base-rewrite` for long documents and multi-step document work, the root fixes the target audience, purpose, output format, scope of changes, and approval status and is in charge of adjustments and final verification, while the children receive self-contained instructions and create source snapshots, output, and comparison ledgers in dedicated work directories. Root reconfirms the actual file and the difference and accepts it, giving priority to the save conditions for snapshot, ledger, and skill.

### Handoff and permissions

- The handoff should include the purpose, target, exclusion, constraints, completion conditions, verification method, and conditions for stopping and confirming when the estimate is exceeded, so that the handoff can be performed without implicit assumptions of conversation.
- Do not extend the authority, scope of approval, or external operation authority passed to the delegatee. Only read-only work is allowed before edit gate approval.
- Do not run work specified as "one by one" or "in order" in parallel. In the shared work tree, only one person is responsible for editing each file, and root will not edit the same range until the person in charge is completed.
- Do not create, select, move, or delete a worktree at the discretion of the delegate. If a separate working directory is required, check user approval and repository-specific operations first.

### Role and model

- For ordinary Codex search, investigation, implementation, and testing workers, explicitly specify model `gpt-6.1-sol` and reasoning effort `low` at startup and on continuation. For task creation/messaging, pass `model="gpt-6.1-sol"` and `thinking="low"`; for subagent spawning, pass `model="gpt-6.1-sol"` and `reasoning_effort="low"`. Choose a supported context fork that permits those overrides, such as `fork_turns="none"` with a self-contained request, rather than `fork_turns="all"`. If the runtime cannot apply the requested settings, report the limitation instead of silently inheriting or substituting settings. This worker rule does not change the primary chat or Advisor settings and does not authorize task creation or writes.
- Role-specific model constraints are applied only to that role before lower-cost models are prioritized. Do not silently replace a judgment role with another role when it is unavailable.
- `Advisor` is dispatched by specifying `gpt-6-sol` if model is not specified in the request, or `high` if reasoning effort is not specified. Rather than using the implicit inheritance of the parent agent's model/effort as the default for the Advisor, each specification made explicitly in the request overrides the corresponding default.
- When specifying the model / reasoning effort of the Advisor, choose a context fork that can override them due to the runtime startup contract. Do not use a mode such as `fork_turns="all"` that fixes the inheritance of the parent's model/effort, but specify `none` or the necessary and sufficient number of history turns if available. If the runtime contract cannot be confirmed, it will not be started by guessing.
- If an agent definition prohibits automatic startup, the agent definition takes precedence over general delegation defaults.
- For other roles and products without a fixed model contract, choose the lowest-cost model that is sufficient to accomplish the task when available. If model-specific adjustments are required, read the corresponding model guide as well.

### Model guide correspondence table

Read the guide corresponding to the selected model as supplementary material only when model-specific adjustments are needed. A model guide must not override the common contract or role/skill-specific contracts; confirm that it is available in the execution environment before applying it.

| Selection model | Compatible guide |
| --- | --- |
| `gpt-6-astra` | `model-gpt-6-astra.md` |
| `gpt-6-sol` | `model-gpt-6-sol.md` |
| `gpt-6-luna` | `model-gpt-6-luna.md` |
| `gpt-5.6` alias or GPT-5.6 family | `model-gpt-5.6.md` |

Models not in the correspondence table or guides that are not available will not be applied by guess.

### Validation of results

- Instead of treating the child's report as evidence of fact, root checks the actual differences, target files, logs, and verification results.
- Even if a child makes a change, the root verifies that the change does not exceed the approved target, operation, or scope. External operations, disclosure, and permission changes are not performed solely on the child's judgment.

### Session identity and reuse

- The reuse unit is `engagement_id`, which represents one explicit decision, and the key is `(root_session_id, engagement_id, role)`. If the decision is different even if the root is the same, it will be a separate engagement.
- Root owns engagement, target epoch, reusability, and shared ledger. The initiator is only responsible for resolving, restarting, creating a new handle, reason for failure, and returning the effective handle, and roles including Advisor, Reviewer, and Respondent do not change handle management.
- Serialize dispatches for the same engagement and role. The same handle is used only when the runtime indicates a successful restart with the same target/epoch, and restart failures and epoch changes are recorded in the ledger and old decisions are not reused.
- The root ID, engagement ID, role, ledger version, target identity, and epoch identity are passed to the Advisor, Reviewer, and Respondent, and when the epoch is changed, the reuse status of the old judgment is re-verified from the actual item.
- Reviewer, Respondent, and Advisor have independent contexts for each role and do not share each other's handles. Advisor output is sourced advice and does not represent root's final decision-making.
- If the revision changes, the coordinator records `review_delta_classification` and the complete manifest/hash of source/destination in the ledger. `REVIEW_PRESERVING` can also inherit only by referring to the Advisor evidence of `CLEAR` linked to the source revision as an append-only edge; do not reattach the source verdict to the destination.
- Packet, child context, and Reviewer/Respondent judgment are revision-bound and do not automatically inherit even in preserving. If the ledger cannot be verified in the current execution context, the edge or hash is missing, or the source verdict is other than `CLEAR`, do not reuse and re-dispatch the required role at the destination revision.

### Evidence child

- Substantive exploration, specification/behavior/dependency confirmation, reproduction, and evidence collection will be delegated to the read-only `scount` Evidence child after confirming the necessity. An exception will be made when the Reviewer/Respondent directly verifies the subject for independence.
- `scount` must not modify files, workspaces, or ledgers; spawn child agents; escalate privileges; perform external changes or sends; or finalize judgments or review states.
- The packet includes the fixed request, source, version or source hash, confirmation method, evidence that could not be obtained, and uncertainty. The root verifies the packet's target and epoch against the actual evidence before accepting it.
- Reuse the child context only when the runtime indicates success in restarting the same target/epoch. If the target or epoch changes, the packet, context, and judgment will be invalidated, and automatic transport and automatic retry will not be performed.
- When performing preserving inheritance, the source evidence id, source/destination revision, delta manifest/hash, classification reason, and verification results are recorded as edges and separated from the packet reuse conditions. Successful restart of runtime alone is not grounds for reusing revision-bound packet/context/judgment.
- If a judgment role returns `NEEDS_EVIDENCE`, root fixes the request, permission range, budget, and termination conditions and re-dispatches the evidence acquisition. If matching is not possible, maintain `NEEDS_EVIDENCE` or gate `BLOCKED`.
