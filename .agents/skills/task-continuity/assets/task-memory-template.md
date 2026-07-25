---
task_continuity: true
status: active
session_id: "{{SESSION_ID}}"
continuous_write_approved: true
memo_path_approved: "{{MEMO_PATH}}"
started_at: "{{STARTED_AT}}"
last_maintained_at: "{{STARTED_AT}}"
last_verified_at: "{{STARTED_AT}}"
---

# Task continuity memo

This memo is disposable secondary state. Revalidate it against current primary
evidence whenever the two conflict.

## Current state

### Objective

{{OBJECTIVE}}

### Completion criteria

- {{COMPLETION_CRITERION}}

### Active constraints and approvals

- Memo creation, continuous maintenance, session registration, and mechanical
  compact append records were approved at `{{APPROVED_AT}}`.
- {{CONSTRAINT_OR_APPROVAL}}

### Verified facts

| Fact | Status | Primary evidence | Verified at |
| --- | --- | --- | --- |
| {{FACT}} | verified | {{EVIDENCE}} | {{VERIFIED_AT}} |

### Inferences and pending questions

| Item | Status | Validation needed |
| --- | --- | --- |
| {{ITEM}} | pending | {{VALIDATION}} |

### Completed work

- {{COMPLETED_WORK}}

### Next actions

1. {{NEXT_ACTION}}

### Risks and blockers

- {{RISK_OR_BLOCKER}}

## Decision log

### {{STARTED_AT}}

- Decision: Activate task continuity.
- Reason: {{ACTIVATION_REASON}}
- Evidence checked: {{INITIAL_EVIDENCE}}

## Maintenance log

### {{STARTED_AT}}

- Created the approved memo and recorded the initial task state.

## Compact emergency records

Mechanical hooks append unverified records below this heading. Do not treat
them as authoritative until a later reconciliation entry verifies or discards
them.

