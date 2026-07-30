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

Maintain a session registry outside the repository that maps:

- Host
- Session ID
- Approved absolute memo path
- `active` or `closed` status
- Approval timestamp
- Optional opaque compact identifier when the host provides one (not used for
  deduplication)
- Installation ownership marker

The storage format and location are environment-specific. Do not put registry
state in the shared skill directory or source repository.

Register a session only after the user approves the memo path, continuous
maintenance, registry entry, and compact append behavior, or when a validated
standing marker records that consent.

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

## Context interface

Model-visible hook context must use clear labels and provide:

- `TASK_CONTINUITY_SESSION_ID`
- `TASK_CONTINUITY_DEFAULT_MEMO_PATH`
- `TASK_CONTINUITY_ACTIVE_MEMO_PATH` when active
- `TASK_CONTINUITY_WRITE_PREAPPROVED=<approved-absolute-directory>` before
  activation, with an empty value when no validated marker exists
- An environment-specific activation instruction
- An environment-specific close instruction
- An environment-specific standing-directory grant instruction

These `TASK_CONTINUITY_*` names are text labels in injected model context. They
are not environment variables and must not be read from the process environment
unless a host adapter separately documents such an interface.

Before activation, context must ask the model to evaluate continuity risk and
invoke `$task-continuity` when its trigger criteria apply. Without standing
approval, it must state that no file may be written before task-scoped
approval. With standing approval, it must state the exact permitted directory
and that another confirmation is unnecessary for covered runtime writes.
After activation, omit the standing-approval field; the active memo path and
session registry entry are sufficient.

After activation, context must instruct the model to read and continuously
maintain the active memo, revalidate it against primary evidence, and update it
before yielding the turn.

Keep injected context short. Do not inject the complete memo automatically.

The complete activation and close commands must be available at `SessionStart`.
Per-turn `UserPromptSubmit` context may omit those commands and use only a
compact risk reminder before activation, or the active memo path and
maintenance reminder after activation. A validated standing-approval memo at
the exact default path uses host-side automatic registration, so missing the
session-start command does not block recovery. This keeps routine turns
inexpensive without removing the manual interface for custom paths and
task-scoped-only approval.

Each host adapter may define a host-local reminder policy. The abstract modes
are `periodic` (emit a short active-session reminder at a configurable long
interval), `boundary` (emit no ordinary-turn reminder), and `strict` (emit a
short reminder on every ordinary turn). A prompt counter belongs to the host's
session state, not to the curated memo. If the policy is not configured, use a
long periodic interval selected by the host adapter.

If a host has no documented model-visible output for an event, do not relabel a
UI-only message as context. Omit that context behavior, report the degradation,
and keep the skill's manual fallback available.

## UserPromptSubmit

When no approved active session exists:

- Add the session ID and proposed default memo path to model-visible context.
- Ask the model to evaluate task continuity risk.
- On routine turns, the activation and close commands may be omitted when they
  were supplied at `SessionStart`; refer to the session-start instructions.
- When no validated standing marker exists, do not create a directory,
  registry entry, memo, `.gitignore`, or `.allow-write`.
- When exact standing approval exists, expose it to the model but do not
  mechanically create a memo; the skill still decides whether continuity risk
  warrants activation.
- When the exact default memo later exists, register it from the event hook
  only after validating the marker and memo frontmatter as specified under
  "Automatic default-path registration".

When an approved active session exists:

- Add the active memo path and maintenance instruction to model-visible
  context.
- On routine turns, omit the activation and close commands; retain them in the
  complete `SessionStart` context.
- Do not rewrite the memo mechanically.

## PreCompact

Before deciding that no active registry entry exists, attempt automatic
default-path registration. This protects a newly created standing-approved memo
when compaction occurs before the next prompt event.

Write only when all conditions hold:

- The session registry marks the session active.
- The registry identifies an approved absolute memo path.
- The memo still declares `status: active`.
- The memo still declares continuous write approval.

Append one clearly marked unverified emergency record containing:

- Timestamp
- Manual or automatic trigger when provided
- Opaque compact identifier when the host provides one
- Transcript path only as an opaque pointer when provided
- A requirement to reconcile after compaction

Do not parse or copy transcript contents. Do not rewrite curated sections. Keep
this hook minimal: only append. Do not deduplicate, merge, or reorganize
records at compaction time; duplicate or repeated emergency records are
acceptable and are consolidated later during reconciliation. Do not block
compaction when the append fails; report the failure through the
host-supported advisory channel.

## PostCompact

For an approved active memo, append one unverified compact-boundary record.
Include the host-generated compact summary only when the event supplies it.
Label the summary unverified.

Do not assume every host provides the summary. Keep this hook minimal: only
append. A retried or repeated event may produce duplicate boundary records;
that is acceptable and is resolved later during reconciliation rather than by
deduplication at compaction time.

## Automatic default-path registration

The host event handler may create a missing registry entry without model-side
file writes only when all of these checks pass:

- The event is `SessionStart`, `UserPromptSubmit`, or `PreCompact`.
- No registry entry already exists for the host and session.
- The memo is the exact default
  `<git-root-or-cwd>/.task-continuity/<session-id>.md`.
- The exact memo directory contains a valid standing `.allow-write` marker.
- The memo is a regular readable file whose frontmatter declares
  `status: active`, `continuous_write_approved: true`, the exact session ID,
  and the exact approved memo path.

The event handler owns this registry write. Do not require the model's
sandboxed shell to write host-local registry state. Never reopen an existing
closed entry, adopt a custom path, or infer activation from a marker alone. On
failure, leave the registry unchanged, do not write the memo, and report an
advisory without blocking the host event.

## SessionStart

When an approved active session resumes or starts after compaction, add
model-visible context that requires:

1. Reading the complete active memo.
2. Rechecking current files, Git state, commands, and relevant external state.
3. Correcting stale memo entries.
4. Appending reconciliation results for unresolved emergency records.
5. Resuming continuous maintenance.

When no active session exists, do not create one.

## Installation ownership

Use a stable ownership identity recognizable without fuzzy matching. Record:

- Host and configuration path
- Exact owned hook events and matcher groups
- Exact generated script paths
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
- Missing or inactive memo: perform no hook write.
- Registry corruption: perform no hook write and report.
- Memo append failure: leave primary work untouched and report.
- Unsupported host feature: degrade explicitly; do not fabricate support.
- UI-only output where model context is required: mark the context behavior
  unsupported and require approval for partial installation.
- Valid JSON or TOML with a host-schema type mismatch: fail before live
  installation.
- Already-correct installation: make no write and change no timestamp.
