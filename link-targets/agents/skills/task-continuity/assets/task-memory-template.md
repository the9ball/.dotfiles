---
task_continuity: true
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

- Memo creation, continuous maintenance, session-to-memo binding, and mechanical
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

### Exact details to preserve

Keep exact error text, failing tests or commands, and unfinished edits whose
paraphrase would lose meaning. Prefer a short excerpt with a reference to the
original log or file; do not copy secrets or whole logs.

| Item | Exact excerpt or reference | Source | Captured at |
| --- | --- | --- | --- |
| {{EXACT_ITEM}} | {{EXACT_EXCERPT_OR_REFERENCE}} | {{EXACT_SOURCE}} | {{CAPTURED_AT}} |

### Completed work

- {{COMPLETED_WORK}}

### Next actions

1. {{NEXT_ACTION}}

### Risks and blockers

- {{RISK_OR_BLOCKER}}

## Decision log

### {{STARTED_AT}}

- Decision: Bind the task-continuity memo to this session.
- Reason: {{CONTINUITY_REASON}}
- Evidence checked: {{INITIAL_EVIDENCE}}

## Maintenance log

### {{STARTED_AT}}

- Created the approved memo and recorded the initial task state.

## Compact emergency records

Mechanical hooks append unverified records below this heading. Do not treat
them as authoritative until a later reconciliation entry verifies or discards
them.
