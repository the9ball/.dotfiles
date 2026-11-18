# Isolated mock owner grants

Production is OFF. Adoption remains BLOCKED. This implementation exercises the approved
`mock-owner-isolated-interval1` design2 input boundary within the existing simulation-only
lifecycle-v2 SQLite prototype. Its base is `f82f960abb7739cf024fb68b5da7b055f15a1554`.
The approved design SHA256 is
`97655f92b6400141007788d17819fb7e33049099ab9bef1139d398ad2f495490`.
The [public design](https://github.com/the9ball/.dotfiles/issues/208#issuecomment-6852245285)
is the source contract. The event schema retains all 24 variants.

Trusted fixture bootstrap constructs `MockOwnerProfile(issuers, grants, sessions,
clock_reader, target_reader)` before opening an empty database with
`EventStore(directory, contract, validator, principals, mock_profile=profile)`.
The issuer registry maps issuer references to `allowed_owner_refs` and `operations`.
The grant registry maps grant IDs to the closed design2 grant field set; its
`profile_version` is `mock-owner-grants-v1`. Sessions are `(object(), description)`
pairs. Descriptions contain `session_ref`, `requester_ref`, `executor_ref`, `actor_ref`,
`allowed_owner_refs`, and `operations`. Bootstrap retains each opaque handle and passes
it to its fixture requester. Identity, rather than object equality or serialized
content, decides handle membership. The profile copies canonical registry bytes;
mutating constructor inputs does not change its authority.

For a single OWNER draft, call
`store.append([draft], command_id, authorization=(grant_id, handle))`.
`intent_sha256(draft)` hashes exactly schema version, gate, revision, actor, event type,
and the complete payload. OWNER batches containing another event are rejected.
Broker batches omit authorization. Existing `Coordinator` broker recovery is reused;
its owner convenience methods do not acquire grant authority automatically.
The target reader takes no append-supplied parameters and returns exactly
`{target, scope_sha256, revision}`. Stop resolution derives target from gate and stop;
gate opening and approval derive it from the gate. Grant issuer, session, actor,
requester, executor, owner, operation, scope, revision, boot, deadline, and use budget
must all match the pinned fixture policy.

Every protected command stores its complete original unnormalized drafts and resolved
`{grant_id, session_ref}` or null authorization. Its fingerprint is the canonical
original request hash. BEGIN IMMEDIATE precedes durable fence/history/dedup reads and
live observations. Fresh commands record the final fixture clock inside the transaction,
normalize event time to that clock, check the current target twice, and persist request,
use, events, blobs and acknowledgement on the existing connection transaction.
Use ordinals are reconstructed from immutable use rows, independently of command dedup.

Protected append returns an immutable `CommitResult` containing status, event IDs and
`execution_permitted=False`. `COMMITTED_ADMISSION` identifies fresh durable admission.
An identical authenticated retry returns `COMMITTED_ACK_ONLY` with its existing IDs,
including after grant expiry. Readback consults neither live clock nor target and
consumes nothing. It grants no effect execution or automatic launch. Changed originals
or another session cannot read back under the same command ID. Commit acknowledgement
loss closes health; reopening and validated replay are required before readback.

Replay verifies policy pinning and bidirectional coverage between commands, requests,
contiguous event transactions and owner uses. It reconstructs exact committed events
from original drafts and recorded envelope/time evidence, then applies existing schema,
actor authentication, event hashes, reducer and T2 effect checks. Historical admission
uses recorded observations rather than today's clock or files. SQLite errors close
health before cleanup; rollback failures remain failures and cannot produce ACKs.
Unclean markers and writer fences retain the existing broker recovery procedure.
Protected reopening requires the exact profile, contract, principals and registries.
Populated legacy databases cannot migrate implicitly; legacy calls retain list results
and remain explicitly unprotected.

Run verification with a concrete Python interpreter and the existing installed
PowerShell image selected in `LIFECYCLE_SCHEMA_PWSH`:

```powershell
& $python -B experiments/lifecycle-v2/implementation/verify_mock_owner_grants.py ".local/lifecycle-v2-owner-grants/interval1/$([guid]::NewGuid())"
```

The output directory must be new. The runner records focused outcomes and worker
cleanup, stops at the first failure, and then invokes the unchanged published 43-check
Git/capture/schema runner in a separate unique integration results directory. No existing
results are overwritten. Focused cases include owner/session substitutions, registry
mutation, direct append denials, exact retry/expiry, target and actual owned-file capture
drift, clock/budget boundaries, writer fencing, SQLite and rollback failures, orphan or
corrupt replay evidence, downgrade/migration refusal, and owned-child transaction crashes.
Expected policy denials count as successful negative cases. No checks were executed by
the implementation worker; the parent owns inspection, formatting and execution evidence.

This cooperative Python fixture is not real authentication, a Python security sandbox,
a trusted clock, rollback-resistant storage, or a production issuer/key/ACL/OS identity.
Capture rechecks detect observed changes but do not freeze files or close malicious
same-user TOCTOU races. Replacing all code/database/policy remains outside this model.
There is no real guardian, dispatch, credential lookup, external effect or production
Skill integration. Existing reducer refusals, including UNKNOWN retirement, remain binding.
