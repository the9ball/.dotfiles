---
name: implementation-planning
description: Use when creating, updating, and reviewing implementation plans or runbooks. Own plan review boundaries, estimates, stop conditions when estimates are exceeded, and history management.
---

# Implementation planning workflow

## Discovery contract

- Host fallback: required

- Positive trigger: Create, update, and review implementation plans or runbooks.
- Negative trigger: Simply editing work notes or short descriptive text without using the plan's ownership scope.
- Conditional dependency: Maintain the common policy kernel and the execution lifecycle's approval, target, and review contract.
- Failure mode: Stop in fail-safe mode if the plan's targets, constraints, estimate basis, or applicable contract cannot be determined.

## Runtime contract

Only when this skill is discovered, the self-contained guide below will be applied as a normative contract. This skill is the normative owner of the plan/runbook and does not load the old guide path.

Resolve the loaded Skill's final existing symlink/junction entity and apply the canonical instruction-root procedure in `link-targets/agents/guides/README.md` (Reference path). Fail closed on missing, ambiguous, broken, or escaping locations; never infer the instruction root from the work root or CWD. Fix the work root and Git target from the request and current Git state, independently of the instruction root.

The ability to execute the plan, approval status, external operations, and acceptance/rejection are left to each existing execution/authorization gate. This Skill does not replace them.

## Guide

Applies to creating, updating, and reviewing implementation plans and runbooks.

Details of implementation-scale estimation and of runbook/plan history management.
Read before creating, updating, or reviewing an implementation plan or runbook.

### The boundary between planning review and post-implementation review

The plan review does not include an exhaustive detailed review of details that do not affect the decisions that should be made before implementation.

The plan review points out matters that, if not determined before implementation, will lead to violation of requirements, actual harm, serious rework, or inability to verify, as well as important omissions regarding scope of approval, acceptance conditions, safety, security, data integrity, compatibility, and irreversible operations. Implementation details and representational completeness that can be verified and adjusted at low cost and safely from implementation results and do not change these decisions should not be pointed out simply because they are missing.

In the post-implementation review, the requirements conformance, actual behavior, regression, danger, and verification results of the fixed implementation target are determined, not the density of descriptions in the plan. The existence of a post-implementation review should not be used as a reason to postpone necessary judgments or significant uncertainties before implementation.

### `承認候補` (Approval Candidates)

All plans have a dedicated `承認候補` (Approval Candidates) section, regardless of type or size. Approval needs that can be reasonably foreseen from information available during planning are candidates; do not include mere speculation. Record candidates discovered naturally during creation or updates, then check the completed plan once for approval candidates. No additional deep investigation is required solely to find candidates.

Even if there are no candidates, do not omit the section; write `なし` (none). This only indicates that the plan was checked and no candidates were found; it does not guarantee that approval needs will not arise at runtime.

For each candidate, write at least **target/operation/cause**. Conditional candidates do not require the exact trigger to be determined, but instead explain what is likely to cause the approval need. Conditions, timing, reasons, etc. may be supplemented only when they are useful for understanding, identification, and re-evaluation at runtime, and if details are provided elsewhere in the plan, they may be referred to. Presentation formats such as bullet and table are not fixed.

#### Identifier

- Add plan-local identifiers `?1`, `?2`, ... to all active candidates, and make the active ID assigned to candidates unique within the current plan.
- The identifier namespace is for each plan artifact. The namespace is maintained for revisions of the same artifact, and is not reset for simple major revisions. You can start from `?1` only when creating a new plan as a separate artifact.
- The ID will be maintained after the revision as long as it can be reasonably determined that the same future approval need is required, and a new ID will be issued if it is unknown. Do not renumber by sorting.
- Do not reuse retired IDs, but keep them as retired ID reservations within the same plan artifact. This shall not hold candidate lineage / history / approval state, but only a set of IDs necessary to prevent reuse. The new ID must be unused for both active and retired, and must not overlap active and retired. The presentation format of reservation is not fixed.
- If 1:1 semantic identity is lost due to split/merge, retire the old ID and issue a new ID to the resulting candidate. Candidate-specific lineage is not recorded.
- Plan candidate ID and runtime approval item ID are different concepts and do not require matching or inheritance.

#### Maintenance

- When updating plan, candidates are updated if there is a reasonable suspicion that the changes will affect the candidates. Don't mechanically rescan the entire plan for every minor edit. When a significantly revised plan is completed, the entire plan is checked as a normal completion check.
- Candidates that no longer require approval are deleted from the `承認候補` (Approval Candidates) section and their IDs are retired. Leave important change history to the existing plan history rules and do not create a candidate-specific state/history store.
- When retiring an ID by deleting, splitting, or merging, the entire current-state content of the current plan is searched for its literal token (e.g. `?3`). Check that no dangling references remain except for retired ID reservations and explicit past history, and if they remain, fix or delete them in the same update. Do not rewrite past history.
- When updating the `承認候補` (Approval Candidates) section and completing the plan, confirm that active candidate ID assignments are unique and that active and retired IDs are not duplicated.
- Obtaining the corresponding approval at runtime does not delete the candidate or change its status to `承認済み` (approved). A candidate is not a runtime approval state, execution permission, or authorization state, and does not create, extend, or revive them. At runtime, evaluate the approval need and existing authorization contract from the current state.

### Why write estimated code amount?

"Simple implementation" is an unverifiable instruction, and it is impossible to determine whether you are violating it during implementation. The estimated number of rows becomes a proxy measure that can be self-checked during generation. The goal is not to reduce the number of lines, but to be able to detect when something deviates from the plan.

### Estimation unit

- Label each step in the implementation procedure with an estimated number of lines. Make it step-by-step instead of file-by-file (if one step spans multiple files, you can add them together).
- Exact accuracy is not required. It is enough to estimate the right order of magnitude. The distinction between 20 lines and 30 lines is meaningless, but the distinction between 30 lines and 300 lines is.
- You can write it with some width (for example, 45 to 65 lines). In that case, excess determination is based on the upper limit of the range.

### Counted and excluded

- Exclude: test code, automatic artifacts, migration generation, configuration files, comments, and empty lines.
- Write a rough estimate of the test code in a separate box. When included in the main body estimate, tests are removed to maintain line count.
- Deleted lines of existing code are not counted.

### If the estimate is exceeded

1. When the number of lines exceeds 1.5 times and +30 lines, stop implementing that step.
2. Categorize and report the reason for the excess. (a) The estimate was lax (b) The requirements were more complex than planned (c) Elements not included in the plan were added.
3. Show countermeasures. In case (c), explicitly check whether the element is really within the scope of the request.
4. Get approval before proceeding.

The reason why the lower limit of the absolute value (+30 lines) is included in the threshold is because if you stop frequently at small steps, there will be a lot of rework and the entire rule will be ignored.

### When implementation is below the estimate

Also report on the downside. Check for any missed requirements, unimplemented branches, or sections left as stubs. Over-implementation is visible in reviews, but under-implementation is invisible.

### What not to do to fit within the number of lines

The number of lines is only a soft goal, and it is prohibited to achieve it by sacrificing the following. If it does not fit, please report as above.

- Drop part of the requirements/specifications and use TODO or stubs
- Eliminate error handling, guard clauses, and input validation
- Packing into one line (nested ternary operators, multi-level method chains)
- Eliminate intermediate variables, shorten naming (contrary to "Do not use short names" of `AGENTS.md`)
- Omitting type annotations and comments

### Indicators to be written in addition to the number of rows

Constraining only the number of lines rewards over-abstraction with fewer lines. “One generic function” has fewer lines than “3 explicit functions,” but it has a higher cognitive complexity. Therefore, be sure to specify the following in your plan. Don't just write the number of lines. Write a number for each step and also write the total at the end of the plan.

- Number of new files to create
- Number of new abstractions to be introduced (classes, interfaces, generics, abstract bases)
- Newly added dependent packages and setting items

Since these cannot be disguised by compression, they may be better suited for detecting excessive implementation than the number of lines.

### Differences in the meaning of the number of rows depending on the layer

The meaning of line counts differs by orders of magnitude across layers. Do not compare them on the same basis.

- DI registration, configuration binding, DTO/type definitions: More lines, but less complexity. Even if it exceeds it, it is almost not a problem.
- Domain logic, state transitions, and conditional branching: Line count excess directly indicates increased complexity. We look at the excess here seriously.
- UI/Template: Markup is large, so estimate only the logic part.

### Runbook/plan history management

- Unless there are more specific instructions, this section applies only to the creation or updating of runbooks and implementation plans that describe operational procedures, and does not apply to regular plans or task memos. In the following, both will be collectively referred to as the "main body".
- The body of the document describes the currently valid procedures and the current assumptions and decisions necessary for their implementation and judgment. The main body is treated as the source of the current content, and the history file is treated as supplementary material.
- Do not create a history file just because it is the first creation or because of minor changes.
- Create `<stem>.history.md` in the same directory as the main body only when the reason becomes worth referencing independently in the future, such as substantial withdrawal or conversion of procedures/policies, handover with decision history, audit/incident tracking, repeated review of the same decision, etc.
- The history records the date of the decision or change, a summary of the change, the reasons for it, and, if applicable, the alternatives and impacts considered. Do not copy the text of the main text, and do not record corrections only to the expression. There is no need to go back and restore minor changes made before the creation of the history file.
- If the main body is under git management, the commit SHA of the repository HEAD at the time of modification can be added as an optional item. To be able to match history and code state in chronological order.
- Create a relative link from the main body only if the history file exists. Do not create empty history files or links to non-existent history.
- If you are unsure whether the change is minor or meets the conditions for creating a history, do not create a history, but create one when a substantial opportunity arises.
- Deleting and organizing existing entries is done only when there is an explicit instruction from the user. Leave entries that explain current behavior and future investigations, and leave them if you are unsure. Deleting history is irreversible, so don't go for it.
- Even when cleaning, do not remove entries silently. Leave a one-line marker at the beginning of the history file saying “Organize entries before YYYY-MM-DD on YYYY-MM-DD (reason: ...)” so the interruption in the history can be identified later. Do not create silent gaps.
