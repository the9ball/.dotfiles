# Task Continuity installation

Lifecycle hooks require a one-time, environment-specific installation performed
by the destination agent (the host).

This document is written primarily targeting Claude Code and Codex. When
installing on another AI (host), read every host-specific reference as "the
equivalent feature on this host" and adapt accordingly. When a host has no
equivalent for a required capability, confirm with the user before installing
rather than silently substituting or skipping it.

The installing agent generates its own runtime implementation and stores it,
together with all session state and ownership records, under the host's own
home directory. Do not add generated scripts to this shared skill directory.

This source contract uses status-free session-to-memo bindings. An already
installed generated helper may still require legacy `status: active` metadata
and expose activation or close commands. Regenerate and reinstall that helper
under this contract before relying on the status-free template. The regenerated
helper must expose exact authorization-only unbinding and must have no close
action. This source-only change does not migrate an installed helper or
establish end-to-end host behavior.

Do not assume Node.js, Python, PowerShell, Bash, fixed configuration paths, or
unchanging hook schemas. Inspect the current environment and official
documentation before generating any runtime script or editing configuration.

## Installation workflow

1. Read `references/hook-contract.md`.
2. Confirm the single host this run targets. Each host is installed
   individually by that host's own agent.
3. Build a capability matrix from current official documentation for each
   event and host. Distinguish event availability, input fields, UI-only
   output, and context that is guaranteed to be model-visible.
4. Inspect locally available runtimes and prefer an already-installed,
   stable, user-accessible runtime.
5. Select stable user-local locations for generated hook code, session state,
   and an installation ownership record.
   Confirm that lifecycle event handlers, rather than model-issued shell
   commands, can write the selected session-state location.
   Also determine whether a platform-specific command override selects only a
   command string or guarantees its execution shell.
6. Present the exact files, configuration entries, commands, and exclusions to
   the user.
7. Obtain approval before creating or modifying files.
8. Generate the smallest implementation that satisfies the supported parts of
   the hook contract. Present any degraded behavior and obtain explicit
   approval before installing a partial integration.
9. Test it entirely against temporary configuration and state.
10. Show the real configuration diff, obtain any required final approval, and
    install it.
11. Verify the installed hook through a new session without creating a memo.
    Manual runtime invocation is fixture evidence only; separately confirm that
    model-visible context is actually delivered by the host.

Do not install a new runtime or dependency without separate approval.

## Configuration invariants

Treat these as acceptance criteria, not suggestions:

- Parse JSON or TOML structurally. Never use blind text insertion.
- Preserve the host's exact container types. When the official schema defines
  an event as an array of matcher groups and each group's `hooks` as an array,
  write arrays even when they contain one element.
- Validate the complete generated structure against the current official
  schema, a host-provided validator, or explicit structural assertions derived
  from that schema. Parsing as valid JSON or TOML is not sufficient.
- Preserve unknown properties, unrelated hooks, unrelated matcher groups, and
  user formatting when the chosen writer supports it.
- Give every owned hook entry and generated file a stable, exact
  `task-continuity` ownership identity. Never recognize ownership by substring,
  prefix, suffix, regex, or another fuzzy match.
- When the host may reinterpret a platform-specific command through the
  session shell, generate a host-local launcher whose invocation contains no
  whitespace or shell metacharacters. Bake fixed executable paths and
  arguments into that launcher instead of relying on `PATH` or the repository
  working directory. Store the launcher outside the shared skill and record it
  as an owned generated file.
- If a host schema does not permit a dedicated ownership field, identify a
  handler by exact normalized structural equality with the ownership record,
  including event, matcher group, command, arguments, runtime path, and marker
  argument.
- Installing an already-correct version must be a true no-op. Do not refresh
  `installed_at`, rewrite formatting, replace identical files, or update any
  configuration, runtime, registry, or ownership-record byte.
- Update an existing owned handler in place only when ownership is
  unambiguous.
- If multiple possible owned handlers exist, stop and report the conflict.
- Never replace an entire `hooks` object to add one handler.
- Write configuration atomically when the platform supports it.
- Do not copy transcript contents into persistent state.
- Do not create a task memo during installation or verification.

## Per-host installation

Verify the destination host's current official documentation before editing its
user or project settings. Configure only the events the host currently
supports, and use the output form the host requires for model-visible context.
Before installation, assert that each configured event and handler container
has the type required by the host's current schema.

Keep host-specific implementation details outside the shared skill files.
Record their paths and ownership markers in the installation ownership record.
The host adapter may also create host-local reminder configuration. Keep the
policy abstract: `periodic` with a long host-selected interval is the default,
`boundary` disables ordinary-turn reminders, and `strict` reminds every
ordinary turn. Store prompt counters in host session state, never in the
curated memo.

Model-visible context must be a documented, guaranteed-model-visible output. Do
not treat a `systemMessage`, a warning, a log line, or UI/event-stream output as
model-visible unless the host's current official documentation explicitly
guarantees that the model receives it. When a host lacks a documented
model-visible output for the prompt-submission or session-start event, mark
automatic risk evaluation and recovery injection unsupported for that host,
offer only the supported mechanical compact behavior, explain the activation
limitation, and obtain explicit approval for that degraded installation.

Host notes (current primary targets):

- Claude Code: hooks live in user or project settings JSON. Assert each event
  and handler container against the current Claude Code schema.
- Codex: hooks live in `hooks.json`, `config.toml`, or another supported layer.
  Confirm that hooks are enabled and that command hooks at the selected scope
  can be reviewed and trusted. On Windows, verify from the current source or a
  fixture whether `commandWindows` controls the execution shell or only the
  selected command text. When a Git Bash, PowerShell, or other session shell
  may reinterpret it, use a generated user-local launcher rather than a quoted
  runtime path in the handler string.

## Required temporary tests

Before touching live configuration, prove all of the following with fixtures:

Use a newly created empty fixture root for each complete run, or safely reset
only paths whose ownership and containment were verified first. Remove or
invalidate any previous result before starting, and always write a current
failure result when the harness exits early. A stale successful result must
never survive a failed or incomplete run.

1. A first installation adds exactly one owned handler per selected event and
   every event/matcher/handler container has the type required by the current
   host schema.
2. A second installation is byte-for-byte and file-set identical across every
   touched or generated file, including configuration, runtime, registry, and
   ownership record. Timestamps stored inside files must not change.
3. Existing unrelated settings and hooks remain semantically identical.
4. A conflicting duplicate owned handler causes a safe failure.
5. An unrelated handler containing the marker text as a substring is not
   treated as owned, updated, or removed.
6. Uninstallation removes only entries whose complete structural identity
   still matches the ownership record.
7. Uninstallation with nothing installed is a byte-for-byte no-op.
8. On a host with documented model-visible output, `UserPromptSubmit` emits
   risk-evaluation context without writing files.
9. On a host without documented model-visible output, the installer reports
   the unsupported behavior and does not claim that UI-only output satisfies
   the context contract.
10. A memo with a validated session-to-memo binding receives one mechanical
    `PreCompact` record only after identity, exact-path, ownership, and approval
    checks pass.
11. New memos and binding records omit lifecycle `status`. Legacy memo and
    registry values `active`, `closed`, unknown, or absent do not change binding
    validity or decide whether a hook writes or recovers.
12. A fixture with a valid binding and a missing memo recreates a fresh memo at
    the exact bound path only after task/session-or-fork identity, target epoch,
    path, ownership, and approval are validated. It notifies the user, marks
    reconciliation required, and never copies transcript contents or restores
    discarded sections.
13. When a hook cannot establish task or target-epoch identity, it supplies
    recovery context and performs no recreation or compact append. A changed
    path, invalid approval, or unbound fork fails closed.
14. The compact-time hook is append-only: a retried or repeated event appends
    another unverified record without error and never deduplicates, merges, or
    rewrites prior records.
15. On a host with documented model-visible output, recovery context identifies
    the bound memo, requires boundary revalidation, and reports when the memo
    was recreated.
16. Paths containing spaces and non-ASCII characters work on the target OS.
17. A standing directory approval is recorded only by an explicit manual grant
    action that creates a path-bound `.allow-write` marker, and a new session
    reuses it only in that exact directory.
18. A pre-existing directory or memo does not by itself establish approval. A
    tracked, symbolic, malformed, or path-mismatched marker remains invalid;
    sibling and nested directories do not match the standing-approved path.
19. Standing approval is injected as one compact field before binding and
    omitted after binding.
20. When hook context is unavailable, a read-only validation of a correct
    default-directory marker reuses standing approval without another user
    confirmation; invalid, tracked, symbolic, or path-mismatched markers do
    not.
21. After a standing-approved default memo is created, `UserPromptSubmit` records
    its binding without a model-issued registry write and follows the reminder
    policy.
22. `PreCompact` can record the same eligible default-path binding before
    appending. An invalid memo or custom path is never auto-adopted. Legacy
    status values do not gate appending; a missing bound memo follows the
    validated recovery procedure.
23. A fixture that denies the model-side command access to the registry still
    passes through the event-handler binding interface supported by the host,
    or the installation is explicitly reported as degraded.
24. A generated launcher preserves stdin, stdout, stderr, and success/failure status when
    invoked through every session shell relevant to the target host. On
    Windows Codex this must include Git Bash and the native shell used by the
    host. The handler invocation itself contains no quoted executable path,
    whitespace, shell metacharacters, `PATH` lookup, or repository-relative
    component. Do not require an exact nonzero numeric code from a parent shell
    that documents or exhibits nonzero-code normalization.
25. Updating a directly invoked owned handler to a launcher updates the exact
    handler identity, generated-file list, and ownership record together. A
    second install is byte-for-byte unchanged, and uninstall removes only the
    recorded launcher and other owned generated runtime files.
26. Task-scoped-only approval is recorded against the exact host, session, and
    memo path. Missing-memo recovery validates that recorded approval without
    requiring `.allow-write`; it never repoints the binding.
27. A custom path requires explicit binding and is never automatically adopted.
    An unbound fork does not inherit its parent's binding.
28. `TASK_CONTINUITY_BOUND_MEMO_PATH` is the preferred path label. The old
    `TASK_CONTINUITY_ACTIVE_MEMO_PATH` is accepted only as a fallback alias;
    normalized disagreement fails closed in both the Skill and cleanup flow.
29. Legacy standing bindings with exact identity, timestamp, ownership,
    `approval_scope: standing-marker`, and matching `approved_directory` are
    accepted only after marker revalidation. Legacy task-scoped bindings are
    accepted only with exact host/session/path, timestamp, ownership, both
    provenance fields absent, and a positively identified legacy writer whose
    explicit activation recorded prior user approval. For each valid shape,
    legacy `status: active` and `status: closed` produce the same binding
    decision.
30. Partial provenance, a missing timestamp or ownership identity, unknown
    legacy writer, mismatched directory, or mixed standing/task-scoped fields
    fail closed. The absence of a standing marker alone never proves
    task-scoped approval.
31. `TASK_CONTINUITY_UNBIND` removes only the exact host/session/path binding
    after explicit user revocation and records an exact revocation in the
    existing registry, including explicit-user-instruction provenance. It
    changes no task or memo lifecycle state and cannot affect another binding.
    Even with the memo and standing marker left intact, later `SessionStart`,
    `UserPromptSubmit`, `PreCompact`, and `PostCompact` events neither recreate
    that binding nor append to the old memo. Model-side writes to the exact
    revoked path are also blocked. A fresh explicit approval can clear only the
    matching revocation and bind that path again.
    A path replacement requires exact unbinding and separate approval of the
    replacement path.
32. Automatic binding rejects a memo or approved directory that is a symbolic
    link, junction, or reparse point. Compact append and missing-memo recovery
    repeat no-follow checks immediately before I/O and use no-follow open or
    create semantics where supported. If the adapter cannot avoid following a
    link or verify the target, it fails closed. Replacing the bound memo or
    parent directory with a link after binding fails closed.
33. Generated `SessionStart` context contains no `TASK_CONTINUITY_CLOSE`, and
    the runtime exposes no close command/action that can mutate a binding when
    task work ends. Authorization-only unbind remains available for explicit
    revocation and removes only the exact approved binding.
34. The complete `TASK_CONTINUITY_UNBIND` instruction is available at every
    `SessionStart`. If the installed helper cannot perform exact unbinding or
    confirm the revocation by read-back, report that revocation was not
    applied. Do not claim old-path hook writes have stopped; require helper
    regeneration or hook disablement/uninstallation first.

Run the host's own configuration validator or launch a disposable new session
when available. If neither is possible, label the result `fixture-only`; do not
describe it as an end-to-end installation pass.

## Uninstallation workflow

1. Read the installation ownership record.
2. Inspect live configuration and locate exact owned markers.
3. Present the entries and files proposed for removal.
4. Obtain approval.
5. Remove only unambiguously owned handlers and generated runtime files.
6. Preserve memos, unrelated hooks, configuration containers, and user state.
7. If ownership is ambiguous, stop instead of deleting.
8. Re-run the fixture showing that unrelated configuration remains unchanged.
