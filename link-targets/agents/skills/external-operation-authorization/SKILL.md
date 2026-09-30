---
name: external-operation-authorization
description: Handles semantic authorization boundaries for operations with external effects, matching just before execution, consumption, retry, read-back, and operation records.
---

# External operation authorization

## Discovery contract

- Positive trigger: Determine the authorization or execution lifecycle of logical operations with external effects such as push, external service/API write, post, publish, deploy, etc.
- Negative trigger: There is no operation with external effects, only local work/verification is performed.
- Conditional dependency: The GitHub service, approval discovery, external posting, and review evidence Skills are each applied only when their own responsibilities arise, and the authorization boundary is not defined redundantly.
- Failure mode: If the target/operation/approval/boundary or execution result cannot be confirmed, stop in fail-safe mode and do not perform any external operations.

## Runtime contract

Only when this skill is discovered, the self-contained guide below will be applied as a normative contract for external-effect authorization. Discovery of approval requests, creation of post content, GitHub-specific API, and review evidence will be entrusted to different owners.

## Guide

Applies to authorization boundary confirmation before execution and lifecycle recording after execution for logical operations with external effects.

### Explicit instruction and local policy kernel

- Push, creating and updating PRs and issues, sending to external services, publishing, sharing, deploying, changing permissions, and creating, updating, moving, and deleting external data are performed only when there is an explicit user instruction. Approval of local file changes does not serve as approval of external operations.
- The target of external operation, logical operation, semantic content range, reflection destination, disclosure range, execution entity, and authority are fixed before execution. Do not interpret mere consent to operating procedures as approval for publication.
- Push is executed only when the target repository, remote, sending ref, and execution conditions are unique, and the actual sending range and command match the instructions. Check the range and conditions immediately before pushing, and stop if there is a commit outside the approved range.
- Force push is performed only when there is an explicit instruction that names the option and the target ref. A non-force push retry is limited to the same remote/ref/commit range/authority that has been confirmed to have no external effect; a different remote/ref, additional push, or permission change requires a new instruction.
- Before the authority boundaries for external operations are determined, only locally closed edits, builds, tests, branch creation, and commits can be performed. Commit reversibility is not a substitute for external approval.

Approval of external operations is tied to the semantic range of operations permitted by the user, rather than to the completed command or transmission body itself.

This range is called the **authorization boundary**.

Boundary is not a mechanism to automatically fix concrete values or hand over approval to subsequent work indefinitely.

Immediately before each trial, the execution entity checks the current target and operation against the boundary, and records the matching results in the operation record.

### Boundary record

When approval is obtained, record at least the following items in one boundary record.

* `authorization_id`
* Basis of user instructions and time of acquisition
* the purpose
* target or safe target selector
* Allowed logical operations, number of successful applications, upper limit of target set
* semantic content range
* Reflection target and disclosure range
* User entity, account, permission route, authority limit
* Preconditions and explicit exclusions
* Completion, cancellation, revocation, and revalidation conditions
* finite retry budget

### Suspension/resume and non-inheritance of approval

Plans, issue texts, REVIEW-SUMMARY, HANDOFF, and task-continuity memos are not substitutes for boundary records.

Merely rereading those documents will not generate, extend, or reinstate the authorization.

After suspending, resuming, or moving the environment, ensure that the original user instructions and unconsumed operational state can be reapplied to the current target.

### Verification just before execution

Even if the specific values differ from those at the time of approval, the method of comparing values is selected depending on the nature of the item.

The items to be compared for identity are the specified target or selector, actor, account, path, reflection destination, public scope, and upper limit of authority.

Each target expanded from a selector is compared for membership in the set allowed by the selector based on enumerable physical identity evidence.

Membership determination of a selector is limited to enumerable physical identity evidence, and semantic inclusion is not the basis for granting membership.

Items to be compared for semantic inclusion are purpose, permitted operation, semantic content, and transmission body.

The items to compare the remaining number are the upper limit of the target set, the number of targets actually expanded, the number of successful applications, and the retry budget.

If the expansion result of selector exceeds the upper limit of the target set, set it as `OUTSIDE_BOUNDARY`, and if the expansion cannot be completed or the number of targets cannot be confirmed, set it as `INDETERMINATE`.

Use the following three values.

| Judgment | Condition | Execution |
| --- | --- | --- |
| `WITHIN_BOUNDARY` | Verify all items with physical evidence and satisfy identity, inclusion, and remaining quantity | Can be done |
| `OUTSIDE_BOUNDARY` | One or more of the confirmed items is out of scope | New approval required |
| `INDETERMINATE` | Unable to confirm required items or determine whether they are within range | Suspended until evidence obtained or new approval |

Do not judge it as `OUTSIDE_BOUNDARY` based solely on changes in the specific text or commands.

If it cannot be determined whether the changed semantic content is included in the boundary, use `INDETERMINATE`.

The order of priority for determination is `OUTSIDE_BOUNDARY` which has been confirmed, `INDETERMINATE` which cannot be confirmed, and `WITHIN_BOUNDARY` which has all been confirmed.

If there are both known out-of-range items and unconfirmed items, set it to `OUTSIDE_BOUNDARY`, and if there is no out-of-range items and only unconfirmed items, set it to `INDETERMINATE`.

### Consumption state and retry

Distinguish between the following states for each logical operation:

* `AVAILABLE`: Haven't succeeded in external effects yet.
* `ATTEMPTING`: Trying after verification.
* `SUCCEEDED_CONSUMED`: Confirmed the external effect and consumed the number of successes.
* `FAILED_NO_EFFECT`: A failure confirmed to have occurred before sending, or confirmed to have had no external effect.
* `OUTCOME_AMBIGUOUS`: Success or failure cannot be determined.
* `INVALIDATED`: boundary or prerequisite has expired.

Logical operations that are confirmed to be successful are not retransmitted.

A failure that is confirmed to have occurred before sending, or that had no external effect, can be retried if the same logical operation, side effect, target, subject, authority, and boundary remain.

The default retry budget is the total of the first attempt and one automatic retry.

Timeout and unknown responses are treated as `OUTCOME_AMBIGUOUS` and are not retransmitted until it is confirmed that they are not applied through read-back, ID verification, and remote state verification.

If it cannot be confirmed by read-back that it has not been applied, stop even if authorization remains.

Do not change targets, services, accounts, credentials, permissions, remotes, refs, public scope, or routes due to retry.

403, 404, authentication change, scope addition, and switching to another CLI/API are not included in automatic retry.

### Normative regression matrix

| Case | Physical Evidence and Expected Judgment | Run or Stop |
| --- | --- | --- |
| Only the concrete transmission body changes and semantic inclusion holds | `WITHIN_BOUNDARY` | Executes without reauthorization and consumes on success |
| Unable to determine specific semantic inclusion | `INDETERMINATE` | Stop until evidence is obtained, and if unresolvable, seek new approval |
| The number of targets expanded into selector exceeds the target set limit | `OUTSIDE_BOUNDARY` | Stop until new approval |
| Unable to confirm completion of selector expansion or number of targets | `INDETERMINATE` | Stop until evidence is obtained and do not run based on guess |
| A semantically similar target that is outside the enumeration set, or whose identity cannot be confirmed | `OUTSIDE_BOUNDARY` or `INDETERMINATE` | Do not use similarity as a basis for permission, and stop it as out of scope or unconfirmable |
| Both known out-of-bounds and unconfirmed items | `OUTSIDE_BOUNDARY` (supersedes `INDETERMINATE`) | Pause until new approval and also obtain evidence of unconfirmed items |
| Retry budget remains for the same operation after confirming that there is no external effect | One automatic retry of the same operation from `FAILED_NO_EFFECT` | Consumes only when retry is successful, no additional automatic retry |
| Unable to check non-application with read-back after timeout | `OUTCOME_AMBIGUOUS` | Stop without retransmitting |
| credential, scope, remote, ref, actor, or permission changes | `OUTSIDE_BOUNDARY` or `INVALIDATED` | Do not retry, pause until new approval |
| Boundary remains unchanged, but review evidence changes in meaning | Authorization remains, review/verification remains in old state | Not executed until new review or verification is completed |
| Only the specific final body of the REVIEW-SUMMARY changes, no important statements are added | `WITHIN_BOUNDARY`, important claims checked | Does not require pre-approval of the final text and records artifacts and read-backs after posting |
| The result of removing invalid CLI options remains the same operation and same boundary without any external effect | `FAILED_NO_EFFECT` | Re-execute within the budget of the initial attempt plus one automatic retry; stop if success or failure is unknown |

### Separation from review evidence

Authorization boundaries and review evidence tied to targets or epochs are treated as separate states.

| Authorization boundary | Review evidence | Treatment |
| --- | --- | --- |
| Valid and unchanged | Unchanged | Can be executed after revalidation at runtime |
| Valid and unchanged | Significant changes | Approval can be maintained, but will not run until a new review or verification epoch is completed |
| `OUTSIDE_BOUNDARY` | Unchanged | New approval required |
| `OUTSIDE_BOUNDARY` | Changed | New approval and new review or verification required |
| `INDETERMINATE` | Unchanged | Stop pending evidence. If resolved as `OUTSIDE_BOUNDARY` or it remains unresolvable, obtain new authorization; only `WITHIN_BOUNDARY` permits proceeding without it |
| `INDETERMINATE` | Changed | Suspended until both approval and review or verification are resolved |
| Unable to confirm validity or identity | Any | Stop execution as `INDETERMINATE`; do not use authorization or any evidence as grounds for execution |

Do not map boundary to `USER_AUTHORIZED`, `PASS_WITH_USER_AUTHORIZATION`, target/epoch evidence.

Execution lifecycle fail-closed identities, review contracts, ledgers, and regular review requirements are maintained as separate contracts.

### Discretion of express delegation

Even if there is an explicit delegation such as `対応して`, `保守して`, "respond", or "maintain", discretion is limited to materialization within the boundary.

Confirmed facts, performed work, verification results, faithful summaries of existing judgments, and ordinary writing quality and presentation adjustments can be determined within a semantic range.

If the agent newly creates any of the following on the user's behalf (in the user's name or voice), additional confirmation is required.

* Promises, deadlines, support responsibilities, risk acceptance
* Legal, Compliance, Financial, Security Policy
* External evaluation, recommendation, criticism, project policy, priority, termination judgment
* Unpublished information, personal experiences, intentions, feelings, unverified facts

Don't misrepresent the source of your judgment, and include the source of your review findings.

### Application to issues and pull requests

Issue text update, REVIEW-SUMMARY posting, Hide or Resolve, push, and Pull Request creation are identified and recorded as separate logical operations.

The set of operations to be included in one issue maintenance delegation is defined as bounded from the target snapshot at the start point and the existing maintenance contract.

Each text update, summary post, Hide, or Resolve operation consumes the number of successes individually.

Do not automatically add comments or other targets added during execution to the operation set.

After the operation, record the operation ID, target, specific operation, external artifact, read-back result, boundary judgment, consumption and retry, skipped, failed, ambiguous operation, and unresolved items.

This record does not replace authorization and does not authorize additional operations.

### Application order

Place only the minimum authorization boundaries necessary at all times in AGENTS.md.

GitHub, issue management, external posting, and execution lifecycle guides apply this contract to logical operations.

Identification of approval requests, bulk acquisition, pending state, and coordination with plans shall be the responsibility of a separate approval request workflow.

The subsequent approval request workflow passes the obtained approval to the execution input as a boundary record in this guide.

The validity, consumption, retry, and post-execution recording of that boundary are the responsibility of this guide, and do not assume that implementation of #48 has been completed.
