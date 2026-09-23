# Hook contract

This contract defines behavior, not an implementation language. The installing
agent must adapt it to the current Claude Code or Codex hook specification and
the runtimes available on the destination system.

## Required events

Install the currently supported equivalents of:

- `UserPromptSubmit`
- `PreCompact`
- `PostCompact`
- `SessionStart`

Do not emulate an unsupported event with unsafe polling or transcript parsing.
For each event, verify separately that the event fires, the required input is
documented, and the required output reaches its intended consumer. Document
any unavailable behavior before installation.

An event name being supported does not imply that its output is model-visible.
UI warnings, event-stream messages, logs, and advisory output do not satisfy a
model-context requirement unless current official documentation says that the
model receives them. A partial integration requires explicit user approval and
must list the unsupported behavior.

## Runtime state

Maintain a session registry outside the repository that binds:

- Host
- Session ID and documented fork lineage when available
- Exact approved absolute memo path
- Approval timestamp and provenance: validated standing marker or explicit
  task-scoped approval for that exact path
- Approved directory when required to revalidate standing approval
- Optional opaque compact identifier when the host provides one (not used for
  deduplication)
- Installation ownership marker

Do not add a task-lifecycle status to new entries. Existing `active`, `closed`,
unknown, or absent status fields are legacy metadata and must be ignored.

Every new binding must record `approval_scope` as exactly `standing-marker` or
`task-scoped`, alongside a nonempty approval timestamp and exact ownership
marker. A standing binding also records `approved_directory`, which must equal
the bound memo's immediate parent and be revalidated against its marker. A
task-scoped binding omits `approved_directory` and records the explicit
user-approved exact path.

Read legacy records only in these complete historical forms:

- Legacy standing: exact host, session, memo path, approval timestamp, and
  ownership marker; `approval_scope: standing-marker`; and the exact approved
  directory. Revalidate the marker and require its directory to equal the
  memo's immediate parent.
- Legacy task-scoped: exact host, session, memo path, nonempty approval
  timestamp, and ownership marker, with both `approval_scope` and
  `approved_directory` absent. Accept this shape only when the installation
  ownership record positively identifies the legacy helper whose explicit
  `activate` action required that timestamp after user approval. The timestamp
  is the old writer's task-scoped approval record.

For both legacy forms, ignore any old status value, including `active`,
`closed`, unknown, or absent. Partial or conflicting provenance, a missing
timestamp or ownership identity, an unknown legacy writer, or a mixture of
standing and task-scoped fields is ambiguous and fails closed. Never infer
task-scoped approval solely from the absence of a standing marker.

Keep explicit authorization revocations in the same session registry as a
separate `revoked_bindings` collection. Each record identifies the exact host,
session lineage, memo path, installation ownership, revocation timestamp, and
`revocation_source: explicit-user-instruction`; it carries no task-lifecycle
status. `TASK_CONTINUITY_UNBIND` must atomically
record that exact revocation and remove only the matching live binding. If the
registry write or read-back fails, report that revocation was not applied.
Automatic binding must check this collection before considering standing
approval and must not recreate any binding automatically for a host/session
lineage with a revocation record, even when a memo and `.allow-write` marker
remain. A later explicit bind may clear only the exact matching revocation
after fresh user approval for that path. Binding a different path requires its
own fresh approval and leaves the old path's revocation intact.
An exact revocation blocks model and hook writes to that host/session/path;
the standing marker does not override it. Only a later explicit bind after
fresh approval restores writes for that exact binding.

The storage format and location are environment-specific. Do not put registry
state in the shared skill directory or source repository.

Create a session-to-memo binding only after the user approves the memo path,
continuous maintenance, registry entry, and compact append behavior, or when a
validated standing marker records that consent.

Store standing approval in `.allow-write` inside the approved memo directory,
not in the session registry or model memory. The marker must record:

- Schema version
- Approved absolute directory
- Approval timestamp
- Approval scope limited to task-continuity runtime writes
- Explicit-user-approval source and installation ownership marker

Require a regular non-symbolic marker, normalize its recorded path according
to the host OS, and require an exact match with the marker's parent directory.
When the directory is inside Git, reject a tracked marker and require Git
ignore rules to exclude it. A hook must not infer consent merely because a
directory, Markdown memo, or unvalidated marker exists. Standing approval does
not authorize deletion, moves, nested-directory writes, or writes outside the
exact directory.

### Memo binding and boundary checks

A registry entry binds one host/session lineage to one exact approved memo
path. It records authorization provenance for covered writes; it does not
represent task activity or completion. At `SessionStart`,
`UserPromptSubmit`, `PreCompact`, `PostCompact`, fork, resume, and recovery
boundaries, revalidate the same task and session-or-fork lineage, target
epoch, exact approved memo path, binding ownership, and approval evidence.
Do not perform this identity check for every ordinary memo write.

For standing approval, revalidate the exact `.allow-write` marker and its
path, schema, scope, source, timestamp, ownership, and Git-ignore rules. For
task-scoped-only approval, the exact path and recorded explicit approval
evidence in the binding are sufficient; do not require a standing marker.
Legacy registry or memo `status` values never authorize or block a write and
never control recovery. Memo existence alone does not create a binding.

Before automatic binding, and immediately before every hook append or recovery
write, validate the exact approved memo directory and memo target with
`lstat`-equivalent, no-follow checks. The directory must be a real directory,
not a symbolic link, junction, or other reparse point. An existing memo must
be a regular file, not a symbolic link or reparse point. Recheck immediately
before I/O so a post-binding replacement fails closed. Use no-follow open or
create semantics and handle-identity checks where the host supports them; if
the adapter cannot avoid following a link or verify the target, fail closed.
After recovery creation, verify the new target has the same properties. When
the memo is missing, validate its exact parent directory before creating it.

If a hook cannot establish task and target-epoch identity at a boundary, it
must provide recovery context for model validation and perform no memo write.
`PreCompact` and `PostCompact` skip appending while recovery remains
unresolved.

## Context interface

Model-visible hook context must use clear labels and provide:

- `TASK_CONTINUITY_SESSION_ID`
- `TASK_CONTINUITY_DEFAULT_MEMO_PATH`
- `TASK_CONTINUITY_BOUND_MEMO_PATH` when a validated binding exists
- `TASK_CONTINUITY_WRITE_PREAPPROVED=<approved-absolute-directory>` before
  binding, with an empty value when no validated marker exists
- An environment-specific binding instruction, labeled
  `TASK_CONTINUITY_BIND`
- An environment-specific authorization-only unbind instruction, labeled
  `TASK_CONTINUITY_UNBIND`, available at every `SessionStart`
- An environment-specific standing-directory grant instruction

During mixed-version rollout, accept
`TASK_CONTINUITY_ACTIVE_MEMO_PATH` only as a legacy alias when the new
bound-path label is absent. Normalize both absolute paths before comparing
them; if both labels are present and differ, fail closed. The legacy label
is only a path alias. It does not establish activity, approval, or status.
Do not provide a task-continuity close instruction or runtime close action.

`TASK_CONTINUITY_UNBIND` revokes only the exact binding identified by host,
session lineage, memo path, and installation ownership. It atomically removes
that live binding and adds the exact `revoked_bindings` record; it changes no
task or memo lifecycle state. Require an explicit user revocation or
path-replacement instruction;
never infer revocation from memo status, task completion, or missing files.
Do not alter another binding. After unbinding, hooks must not write to or
recover the old path, and the model must not write to it either. A replacement
requires unbinding the exact old record, separate approval for the new exact
path, then creating a new binding. Never repoint or keep two paths for one
host/session lineage. If the adapter cannot
perform exact unbinding, report that revocation has not been applied. Require
the helper to be regenerated or its hooks disabled or uninstalled before
claiming that mechanical writes to the old path have stopped. Until then, do
not claim that maintaining another path prevents the old hooks from writing.

These `TASK_CONTINUITY_*` names are text labels in injected model context.
They are not environment variables and must not be read from the process
environment unless a host adapter separately documents such an interface.

Before binding, context must ask the model to evaluate continuity risk and
invoke `$task-continuity` when its trigger criteria apply. Without standing
approval, it must state that no file may be written before task-scoped
approval. With standing approval, it must state the exact permitted
directory and that another confirmation is unnecessary for covered runtime
writes. After binding, omit the standing-approval field; the bound path and
validated approval evidence are sufficient.

After binding, context must instruct the model to read and continuously
maintain the bound memo, revalidate it against primary evidence, and update it
before yielding the turn. Boundary context must additionally require the
fork/resume/compact/recovery revalidation above; ordinary-turn maintenance
does not require a per-write registry or frontmatter check.

Keep injected context short. Do not inject the complete memo automatically.

The complete binding command must be available at `SessionStart`. The complete
unbinding command must also be available there on every session. Per-turn
`UserPromptSubmit` context may omit either command when it was supplied at
`SessionStart`; refer to those instructions. A validated standing-approval
memo at the exact default path uses host-side automatic binding, so missing
the session-start command does not block recovery. Custom paths and
task-scoped-only approval require the explicit binding interface.

Each host adapter may define a host-local reminder policy. The abstract modes
are `periodic` (emit a short memo-maintenance reminder at a configurable long
interval), `boundary` (emit no ordinary-turn reminder), and `strict` (emit a
short reminder on every ordinary turn). A prompt counter belongs to the
host's session state, not to the curated memo. If the policy is not
configured, use a long periodic interval selected by the host adapter.

If a host has no documented model-visible output for an event, do not relabel
a UI-only message as context. Omit that context behavior, report the
degradation, and keep the skill's manual fallback available.

## UserPromptSubmit

When no valid session-to-memo binding exists:

- Add the session ID and proposed default memo path to model-visible context.
- Ask the model to evaluate task continuity risk.
- On routine turns, the binding instruction may be omitted when it was
  supplied at `SessionStart`; refer to the session-start instructions.
- When no validated standing marker exists, do not create a directory,
  registry entry, memo, `.gitignore`, or `.allow-write`.
- The absence of a standing marker does not prevent a binding after the user
  explicitly approves a task-scoped path. Use the binding interface to record
  that exact path and approval evidence; do not create `.allow-write` without a
  separate standing approval.
- When exact standing approval exists, expose it to the model but do not
  mechanically create a memo; the skill still decides whether continuity risk
  warrants a memo.
- When the exact default memo later exists, record its binding from the event
  hook only after validating the marker and required memo metadata specified
  under Automatic default-path binding and confirming that this host/session
  lineage has no revocation record. If revoked, do not auto-bind or write; show
  the user the explicit-bind interface. If an existing binding points to a
  missing memo, use Boundary recovery and missing memo instead of treating
  legacy status as a reason to stop.

When a validated binding exists:

- Add the bound memo path and maintenance instruction to model-visible
  context.
- On routine turns, omit the binding instruction; retain it in the complete
  `SessionStart` context.
- Do not rewrite the memo mechanically.

## PreCompact

Before deciding that no binding exists, attempt automatic default-path
binding. This protects a newly created standing-approved memo when
compaction occurs before the next prompt event.

Write only after boundary identity, exact path, binding ownership, and
approval provenance have been validated, and all of these conditions hold:

- The binding identifies the exact approved absolute memo path.
- The memo is a regular file whose metadata declares
  `task_continuity: true`, `continuous_write_approved: true`, the exact
  session ID, and the exact approved memo path.
- The binding's recorded approval evidence is valid. Revalidate the exact
  `.allow-write` marker for standing approval; for task-scoped-only approval,
  validate its explicit path-bound evidence in the binding without requiring
  a standing marker.

Ignore legacy memo or registry `status` values, including `active`, `closed`,
unknown, or absent. If the memo is missing, first complete Boundary recovery
and missing memo. If the hook cannot establish task or target-epoch identity,
provide recovery context and skip the append.

Append one clearly marked unverified emergency record containing:

- Timestamp
- Manual or automatic trigger when provided
- Opaque compact identifier when the host provides one
- Transcript path only as an opaque pointer when provided
- A requirement to reconcile after compaction

Do not parse or copy transcript contents. Do not rewrite curated sections.
Keep this hook minimal: only append. Do not deduplicate, merge, or reorganize
records at compaction time; duplicate or repeated emergency records are
acceptable and are consolidated later during reconciliation. Do not block
compaction when the append fails; report the failure through the
host-supported advisory channel.

## PostCompact

For a validated binding and eligible bound memo, append one unverified
compact-boundary record. Include the host-generated compact summary only
when the event supplies it. Label the summary unverified.

Run the same boundary identity, path, ownership, and approval validation as
for `PreCompact` before appending. Ignore legacy lifecycle status values. If
the memo is missing or recovery is unresolved, skip the append and provide
recovery context.

Do not assume every host provides the summary. Keep this hook minimal: only
append. A retried or repeated event may produce duplicate boundary records;
that is acceptable and is resolved later during reconciliation rather than
by deduplication at compaction time.

## Automatic default-path binding

The host event handler may create a missing binding without model-side file
writes only when all of these checks pass:

- The event is `SessionStart`, `UserPromptSubmit`, or `PreCompact`.
- If a registry record already exists for the host and session, validate it as
  a binding using its identity, path, ownership, and approval evidence only.
  Ignore its status and never replace it automatically.
- If `revoked_bindings` contains a record for this host/session lineage, do not
  automatically bind any path, even when the standing marker and memo remain
  valid. The exact revoked path is never eligible for writes. A path listed as
  both bound and revoked is inconsistent; fail closed.
- Create a new binding only when no registry record exists and all following
  default-path and standing-approval checks pass.
- The memo is the exact default
  `<git-root-or-cwd>/.task-continuity/<session-id>.md`.
- The exact memo directory contains a valid standing `.allow-write` marker.
- The approved directory and existing memo pass the no-follow directory/file
  checks defined under Memo binding and boundary checks.
- The memo is a regular readable file whose frontmatter declares
  `task_continuity: true`, `continuous_write_approved: true`, the exact session
  ID, and the exact approved memo path. Do not inspect or require a `status`
  value; it does not gate registration.

Record the event-owned binding with its exact path, approval timestamp,
`approval_scope: standing-marker`, approved directory, and installation
ownership. Do not require the model's sandboxed shell to write host-local
registry state. Do not adopt a custom path or infer approval from a marker or
memo alone.

A custom path or task-scoped-only approval requires the explicit
`TASK_CONTINUITY_BIND` interface and a record of user approval for that exact
path. New task-scoped records set `approval_scope: task-scoped`, preserve the
approval timestamp and exact path, and omit `approved_directory`. A
task-scoped binding does not require `.allow-write` during later recovery.
Existing status fields do not create, suppress, reopen, or revoke a binding.
An explicit bind after revocation clears only the exact matching revocation
record when fresh approval and the new binding are committed together. On
failure, leave the registry unchanged, do not write the memo, and report an
advisory without blocking the host event.

## Boundary recovery and missing memo

At `SessionStart`, `UserPromptSubmit`, `PreCompact`, `PostCompact`, fork,
resume, or an explicit recovery event, a validated binding may point to a
missing memo. The event handler must:

1. Confirm the same task and session-or-fork lineage, target epoch, exact
   bound path, binding ownership, and approval provenance.
2. For standing approval, revalidate the exact `.allow-write` marker. For
   task-scoped-only approval, validate the recorded explicit approval and
   exact path without requiring a standing marker.
   Revalidate the exact parent directory with no-follow metadata checks; reject
   a symbolic link, junction, or reparse point before creating the memo.
3. Notify the user that the memo was missing and its previous contents are
   unavailable.
4. Recreate a status-free memo from the installed template at the exact
   bound path only when task and target-epoch identity are established. Do
   not copy transcript contents or infer discarded sections.
5. Record in the fresh memo that model-side reconciliation is required.
6. Recheck the recreated target as a regular non-link file before any compact
   append, then continue with that boundary's normal append or model-visible
   recovery context.

A binding proves host/session lineage, path, and approval record; it does not
by itself prove the current task meaning or target epoch. If the event cannot
establish task or target-epoch identity, do not recreate or append. Provide
recovery context for the model to validate identity from current conversation
and primary evidence. `PreCompact` and `PostCompact` must skip appending while
recovery remains unresolved.

If any identity, path, approval, or ownership check fails, do not recreate or
append. Never repoint a binding to another path. Legacy `active`, `closed`,
unknown, or absent status fields do not affect these checks.

If the user revokes approval or explicitly requests a different memo path,
first perform `TASK_CONTINUITY_UNBIND` for the exact old host/session/path
record. Obtain approval for the replacement path and create a fresh binding
only after that authorization succeeds. Until then, do not write or recover
through the old binding. If exact unbinding is unsupported, do not bind the
replacement; maintain it without hook recovery.

## SessionStart

When a validated memo binding resumes, starts after compaction, or crosses a
fork/resume/recovery boundary, add model-visible context that requires:

1. Reading the complete bound memo.
2. Revalidating task and session-or-fork lineage, target epoch, exact memo
   path, binding ownership, and approval evidence. Ignore legacy status.
3. Rechecking current files, Git state, commands, and relevant external state.
4. Correcting stale memo entries.
5. Appending reconciliation results for unresolved emergency records.
6. Resuming continuous maintenance.

When no binding exists, provide continuity-risk context and the bind interface
as applicable. When a revocation exists for the host/session lineage, identify
the revoked path and tell the model and hooks not to write or recover it. Any
new path requires fresh explicit approval through `TASK_CONTINUITY_BIND`; never
bind automatically or clear an old path's revocation. Keep the unbind
instruction available. Do not inherit a parent session's binding into an
unbound fork.

## Installation ownership

Use a stable ownership identity recognizable without fuzzy matching. Record:

- Host and configuration path
- Exact owned hook events and matcher groups
- Exact generated script paths
- Exact generated launcher paths when the host adapter requires one
- Exact ownership marker
- Installation version or timestamp
- Runtime executable used

When the host schema permits a dedicated ownership field, require exact field
equality. Otherwise record the complete normalized handler identity: host,
configuration path, event, matcher group, handler type, command, arguments,
runtime path, and exact marker argument.

Do not use substring, prefix, suffix, regex, or case-folded partial matching to
claim ownership. Marker text inside an unrelated command is not ownership.

Installation may update only an entry whose complete identity matches the
ownership record. Uninstallation may remove only entries and files recorded as
owned whose complete current identity still matches. Any mismatch is
ambiguous ownership and must stop the operation.

Reinstalling an already-correct version is a true no-op. Preserve every byte
and file in configuration, runtime, registry, and ownership state, including
stored installation timestamps.

## Command execution compatibility

Treat platform-specific command fields and execution-shell selection as
separate capabilities. Do not assume a Windows-specific command override is
executed directly or by a native Windows shell unless current host behavior
guarantees it.

When the host can pass the selected command text through Git Bash, PowerShell,
or another session shell, generate the smallest host-local launcher that
provides one shell-neutral handler invocation. Require that invocation to use
an absolute user-owned path with no whitespace or shell metacharacters. Put
fixed runtime paths and arguments inside the launcher, preserve stdin, stdout,
stderr, and success/failure status, and never resolve the runtime from `PATH`
or the repository working directory. Do not claim exact numeric preservation
when the selected parent shell normalizes external nonzero exit codes.

Keep generated launchers, runtimes, and ownership records under the host's
user-local state; never add them to the shared skill. Record the exact launcher
path and handler identity so install, update, and uninstall remain idempotent
and cannot claim unrelated files. Re-review or re-trust the hook when a host
uses the handler hash as its trust identity.

## Configuration conformance

Preserve the exact container types required by the current host schema. In
particular, when event values are arrays of matcher groups and matcher-group
`hooks` values are arrays of handlers, singleton values must remain arrays.

Validate more than parseability. Use a current host validator when available;
otherwise assert every required field, type, array boundary, matcher rule, and
handler form from official documentation. If a real host cannot validate or
load the result, report the test as fixture-only.

## Failure behavior

- Malformed configuration: stop before writing.
- Missing runtime: choose another existing runtime or request approval to
  install one.
- Ambiguous ownership: stop and report.
- Missing memo: perform boundary recovery only when the exact session binding
  and its approval provenance validate. A standing binding requires the
  standing marker; a task-scoped binding uses its exact recorded approval.
  If task or target-epoch identity cannot be established, provide recovery
  context and perform no write. A valid default memo may be auto-bound only
  under Automatic default-path binding. Ignore lifecycle status fields.

- Registry corruption: perform no hook write and report.
- Memo append failure: leave primary work untouched and report.
- Unsupported host feature: degrade explicitly; do not fabricate support.
- UI-only output where model context is required: mark the context behavior
  unsupported and require approval for partial installation.
- Valid JSON or TOML with a host-schema type mismatch: fail before live
  installation.
- Already-correct installation: make no write and change no timestamp.
