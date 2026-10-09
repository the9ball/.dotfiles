---
name: approval-request-workflow
description: Used to discover and hand off explicit permission or judgment needed for the next autonomous execution interval. It is not triggered by unrelated executions.
---

# Approval request workflow

## Discovery contract

- Host fallback: required

- Positive trigger: Explicit permission or judgment discovery is required before execution can proceed.
- Negative trigger: No approval request, just normal build/test/review.
- Conditional dependency: The external-operation-authorization Skill is applied only when an authorization-boundary responsibility arises. Redesign material is contained in this Skill's non-runtime Design section and is not applied in ordinary runtime.
- Failure mode: If a required dependency contract cannot be resolved, do not rely on guesswork, instead stop in a fail-safe manner and report.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

The common contract for execution authorization applies link-targets/agents/skills/external-operation-authorization/SKILL.md only when the obligation occurs. When reconsidering runtime workflow design decisions, refer to the non-runtime Design section of this skill.

## Guide

A portable runtime contract that discovers and aggregates the approval requests required before execution, interprets the responses, and handoffs them to execution.
This workflow does not create new approval requirements, nor does it redefine the establishment, validity, permission boundary, consumption, retry, read-back, review evidence, or execution lifecycle of existing approvals.

### Basic principles

- Approval items should only be those that require explicit permission/judgment before the current execution can proceed autonomously due to applicable higher-level rules, guides, skills, user instructions, etc. This workflow itself does not convert process step, automatic review, checkpoint, and build/test into approval items.
- Collection, ID, lineage, and semantic identity on workflow are for display and tracking purposes, and do not represent approval status, importance, execution order, execution authority, permission boundary, or validity.
- If the existing applicable approval/delegation meets the requirements, it will not be re-requested. Establishment, validity, consumption, etc. are determined by the existing rules that own them.
- “Autonomous execution interval” is a convenient name for an execution range that can continue without obtaining new approval; it has no independent state, ID, table, or mathematical maximum. Unless there is a reasonable reason to stop, do not subdivide it unnecessarily.

### 1. Discover approvals needed for the next autonomous execution interval

From the available work context, reasonably identify the approvals currently needed to start the next autonomous execution interval.

If an approval candidate exists in a plan, check it as a required input. However, it is not an authoritative or exhaustive list; reevaluate the need based on the current state. This workflow does not specify how candidates are generated, their heading or format, or their identifiers.

Do not scan the entire future autonomous execution interval merely to collect approvals. Even if a future approval need is recognized early, do not interrupt the current interval or collect that approval in advance solely for that reason.

If the identification itself requires user judgment or other approval, present the known range and stop.

### 2. Aggregate presentation while remaining independent

Do not combine multiple approval items into a single approval boundary. Each item can remain independent and be presented together in a single collection.
Each item is briefly indicated so that the target, range, and operation can be determined. Supplement information only if conditions, reasons, irreversibility, scope of disclosure, authority, important data, etc. are important to the decision.

A runtime item derived from an approval candidate such as a plan indicates provenance. If the candidate has an existing identifier, use it; if not, use its existing label or other referenceable expression. If none is clear, use a general display such as `（計画上の承認候補）` (“planned approval candidate”). Multi-parent mapping is not required even if it is derived from multiple candidates.

### Collection and ID

- Each collection has a display prefix and advances as `A..Z, AA, AB...`.
- Do not reuse closed prefixes within the same work unit. A new work unit may start at `A`.
- When presenting the runtime item ID to the user for the first time, it is automatically assigned to the display order as `A1`, `A2`, ....
- An ID once presented will not be renumbered/reused. Allow missing numbers.
- Items added later to the same collection use the next unused number, and do not change the existing ID depending on the display position.
- Does not require persistent state stores for prefixes and IDs.

### 3. Interpret answers and reconsider if necessary

Specify `回答対象` each time the approval workflow is presented. If there is no target, set it to `回答対象: なし`.

- A normal unqualified affirmation (e.g. `OK`, `進めて` ("proceed")) is treated as affirmation of the entire `回答対象` specified at that time. Give priority to any user-specified limitations or exclusions.
- For a normal negation, if `回答対象` contains one item, treat it as rejection of that item. If it contains multiple items, ask which one rather than guessing.
- In a partial response, do not presume that omitted items are approved or rejected. Previously presented items that have not changed may be listed again under `回答対象` by ID alone.
- If it is unclear which presentation content the answer is aimed at, it will not be applied automatically.

If rejection prevents entry into the next autonomous execution interval, do not execute the rejected path; reconsider the alternative. If the alternative needs a new approval before handoff, add it to the same collection. If no alternative can replace it, stop because work cannot proceed. After reconsideration, do not request again any other approvals that remain independently applicable.
### Update/representation/new/withdrawal

- **Update**: When updating the presented content of the same unfinished, unapproved logical operation, you may keep the same ID. Mark the next presentation as `更新: A2` (“Update: A2”) once and show the full current approval content. The agent determines whether an update applies.
- **Re-presentation**: If the same rejected, unfinished logical operation is considered again, issue a new ID and identify its direct parent once, for example `B1（A3の再提示）` (“B1 (re-presentation of A3)”). If the content is also updated, the display may show both the update and re-presentation. Ancestry history is not required.
- **New**: Merging/splitting, another operation after a completed/consumed operation, an operation that is needed again after being withdrawn, and an operation that cannot be reasonably determined to be the same unfinished logical operation are considered new items. Don't guess unknown lineages.
- **Withdrawal**: If a presented item is no longer needed for a reason other than explicit rejection, show `撤回: A2` (“Withdrawal: A2”) once. Do not show a withdrawal again when refusing. Do not reinstate a withdrawn ID; create a new item if a similar operation is needed later. Even a withdrawal-only notice must specify `回答対象: なし`.

Continuing, updating, or re-presenting the ID does not mean the validity of the existing approval at runtime.

### 4. required approvals gate and handoff

Handoff to execution after confirming that the approvals needed to start the next autonomous execution interval have been met under the applicable rules and any necessary re-evaluation is complete.

Collection is closed at this handoff, not when all answers are obtained. If a new approval item is found before handoff, add it to the same collection. If a new approval need is found after handoff, a new collection is started instead of reopening the closed collection.

### If new approval is required during an autonomous execution interval

If a new approval is required to complete the current autonomous execution interval, do not begin the operation that needs approval. Proceed to a safe, consistent, and reasonable stopping point, then move to the approval phase.

Approval candidates discovered naturally while reaching a stopping point may be used, but do not delay execution just to increase their number. Even if an approval needed only for a future interval is discovered early, do not interrupt the current interval; rediscover it at a later boundary. No dedicated persistence store is provided.

There is no special rule that allows replay-safe work to occur in the next interval in advance because of idle time waiting for approval, and whether or not parallel execution is generally possible is left to the existing rules.
### Reconstruction

Compact or the passage of time alone does not constitute reconstruction. Reconstruction is used when the continuity of the execution state cannot be guaranteed and the current state needs to be reconstructed from memo/context, etc.

Do not restore the old collection. Instead, rediscover the necessary approval items from the current remaining work and use a new collection / the next prefix. If it is the same work unit, do not return it to `A`.

Reconstruction does not invalidate the existing approval itself. If the existing judgment is still applicable, no duplicate requests will be made.

### Responsibility boundary

This workflow handles discovery of approval needs, division into runtime items and aggregated presentation, collection/display IDs, `回答対象` and response interpretation, display updates, re-presentation and withdrawal, reconsideration after rejection, handoff to execution, and reconstruction of a collection.

The following are left to their existing owners:

- Conditions for prior statement to be valid approval
- Recording and determining semantic permission boundaries
- approval consumption, retry, read-back, execution results
- review evidence / revision epoch / execution lifecycle
- Generation/format/identifier of plan approval candidate

For design changes or workflow redesigns, refer to the non-runtime Design section below. This does not change the runtime contract and is not normally applied at runtime.


## Design (nonruntime)

This section preserves design rationale, alternatives, and non-normative scenarios for future redesign. It is not loaded as a runtime contract and does not change the Guide section above.

Records the design rationale, responsibility boundaries, rejected alternatives, and decision-support scenarios for the approval-request-workflow Skill's runtime contract.
It is usually not needed in runtime and is referenced when editing, redesigning, making uncertain decisions, and reviewing workflows. The scenarios in this section are non-normative, and if they conflict with the Guide, the Guide takes precedence.

### Design intent

#### Discovery is limited to the “next autonomous execution interval”

Approving an entire plan in strict sequence before execution collects approvals early for future intervals whose execution status is not yet determined, increasing unnecessary interruptions and stale decisions. Therefore, discover only approvals currently needed to start the next autonomous execution interval.

An “autonomous execution interval” is not an independent state. A mechanism for calculating its maximum length would make this workflow own the execution planner, so applicable rules and agents determine reasonable stopping points.

#### Collection is batching, not permission boundary

Being able to present multiple independent approval items at once reduces round trips, but making a collection a single authorization boundary erodes the existing authorization contract. Therefore, the collection / prefix / ID is only responsible for display and response tracking, and the permission semantics of each approval item are left in the existing rules.

If a collection is closed “when all answers have been collected,” items that were discovered after the answer or before handoff will be unnaturally separated into another collection. By setting the handoff to execution as the close point, the group of approval phases and the execution boundary are aligned.

#### Limit IDs to lightweight conversational identities

The runtime ID will be assigned when it is presented for the first time. This is because if you number the unpresented candidates first, it becomes easier for the workflow to own the plan candidate's format and permanent management.

Maintaining identity helps track semantic identity, but does not prove the validity of authorization. The existing owner will determine approval applicability, permission boundaries, consumption, etc. after content updates.

#### Reconstruction does not restore collection history

When restoring an old collection in a state where execution continuity cannot be guaranteed, it is easy to mistake the reproduction of the display state for the restoration of the permission state. A new collection is created by re-discovering the current remaining work, while existing independently valid approvals are maintained through normal judgment.

### Responsibility boundary

The approval-request workflow owns “what to request the user to judge now” and “which runtime item should the answer be applied to”.

This workflow does not own the following:

- Conditions for valid approval and semantic authorization boundary
- approval runtime effectiveness, consumption, retry, read-back, and result logging
- review evidence、revision / review epoch、execution lifecycle
- Generation of approval candidate on plan, dedicated section, format, identifier
- The overall external-operation model for GitHub / Issue maintenance

Due to this separation, identity / lineage and execution authorization on workflow are not automatically mapped.

### Rejected alternative

- **Strict serial for the entire plan**: Do not adopt this as it collects approvals up to the future state and stops execution unnecessarily.
- **Preemptive approval of future intervals**: If the current interval is interrupted just for early recognition, it will increase stale / unnecessary approval, so it will not be adopted.
- **Replay-safe work special rule while awaiting approval**: Not adopted because it would let this workflow override the general rules for parallel execution.
- **Fixed format/numbering of plan candidates**: Not adopted as it encroaches on the responsibility of plan authoring.
- **Workflow-specific revision/hash/state store**: Not adopted as it overlaps with the authorization / review lifecycle and exceeds the lightweight display workflow.
- **Uniform re-obtainment of existing approvals when resuming**: Not adopted because even independently valid approvals are invalidated.

### Non-normative scenario

#### Multiple independent approvals on the same starting boundary

If the next execution interval requires a publishing operation and a different authority decision, it can be presented in the same collection as `A1`, `A2`. If the user answers `A1だけOK` ("only A1 is OK"), `A2` is not guessed and treated as pending. The authorization semantics of both items are determined by their respective existing rules.

#### Added item is found before handoff

After answering `A1`, if it is found that separate approval is required during re-evaluation before handoff to execution, add it to the same collection as `A2`. If a new need is found after the necessary approvals are satisfied and handoff is performed, a new collection is started from `B1`.

#### Choose alternative after rejection

If `A2` is rejected and an alternative that can accomplish the goal without that operation requires a new approval, add it to the next number in the same collection as long as it is before handoff. If the existing approval of `A1` is also independently applicable to the alternative, the workflow does not require re-acquisition.

#### Update presentation content

If unacknowledged `A2` is materialized with the same unfinished logical operation, `更新: A2` (“Update: A2”) and the current contents can be presented in full text while maintaining the same ID. However, it is not determined from the workflow ID whether a delayed response to an old proposal is also valid for new content, and if it is ambiguous, it will not be applied automatically.

#### Reconstruction is necessary

If the continuity of the execution state cannot be guaranteed and the current remaining work is rebuilt, the old `A` collection will not be reproduced and discovery will be performed again with the collection of the next prefix. If a previous approval is still applicable on an existing authorization contract, the workflow will not revoke it.
