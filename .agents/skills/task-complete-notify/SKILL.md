---
name: task-complete-notify
description: Use when the user explicitly asks to arm a one-shot ntfy notification for a selected Codex thread.
---

# Task-complete notification

Use this skill only when the user explicitly asks to arm a task-completion notification. It is a best-effort notification for one explicitly selected Codex thread; it does not infer the current thread and it does not inspect prompts or logs to compose notification text.

## Scope

The first adapter is Codex on Windows. Runtime state is isolated under the
resolved Codex home as `$CODEX_HOME\.task-complete-notify` (or the user's
`.codex` home when `CODEX_HOME` is unset), so separate homes such as
`.codex` and `.codex-personal` never share requests or locks. WSL callers must
use the Windows PowerShell helper for all state and lock operations and must
inherit the active session's `CODEX_HOME`.

The Codex `Stop` hook is the primary completion detector. Register it manually in the user's Codex hook configuration after reviewing the generated command and running the canary described below. The JSONL watcher is a fallback only when the Stop-hook canary is not viable; do not enable both as independent senders.

## Permission prerequisites

The skill does not edit Codex configuration or select a permission profile. Before
enabling the hook or fallback watcher, verify the exact profile and sandbox used
by the target session. The minimum required access is read-only access to the
same home's `session_index.jsonl` and rollout files, write access only to that
home's `$CODEX_HOME\.task-complete-notify`, and HTTPS access to `ntfy.sh`.
Do not broaden access to an entire user profile or filesystem. A canary run
through the exact production hook path must establish whether profile and
legacy sandbox enforcement apply to the child process.

## Arm a notification

For a Windows PowerShell caller, run:

```powershell
pwsh.exe -NoProfile -NonInteractive -File "<skill-dir>\scripts\arm-notification.ps1" `
  -Thread "codex://threads/<UUID>" `
  -Message "Build finished"
```

The canonical target is `codex://threads/<UUID>`. An arm input may contain a
raw UUID or canonical URI inside ordinary labels, quotes, Markdown, or other
surrounding text. UUID candidates use ASCII hexadecimal D-form (`8-4-4-4-12`)
with standalone ASCII boundaries; repeated occurrences of the same UUID are
allowed, but two different candidates are rejected as `thread_ambiguous`.
Inputs over 4 KiB UTF-8, zero candidates, invalid UUIDs, the legacy
`codex://<UUID>` form, and URI path/query/fragment decorations are rejected.
Only the arm boundary uses this relaxed extraction. Hook input, transcript
metadata, state, and watcher values continue to require the strict complete
canonical/raw form.

Before an arm request creates state, the helper verifies that the target is
managed by the current Codex home: an exact `session_index.jsonl` ID match and
an active rollout whose first `session_meta` has matching `id` and
`session_id`, `thread_source: "user"`, and no parent fields. Unknown,
archived, or other-home IDs fail closed as `thread_not_managed` and do not
create `.task-complete-notify`.

`-Message` is optional. When omitted, the exact body is `Task completed`. An explicit message is a literal, single-line string of at most 256 UTF-8 bytes. Empty or whitespace-only values, leading/trailing whitespace, CR/LF/NUL, Unicode control characters, U+2028/U+2029, and unpaired surrogates are rejected. The literal is stored in the active request and becomes an external-send authorization when arm succeeds; do not put secrets or sensitive business data in it.

Re-arming an existing `armed` or `attempting` request is idempotent and does not replace its generation or message. An orphaned `attempting` request can be consumed by a later explicit arm and replaced by a new generation.

For a WSL caller, do not pass the message as a Windows process argument. Send an operation envelope through stdin:

```bash
printf '%s\n' '{"operation":"arm","thread":"codex://threads/<UUID>","message":"Build finished"}' \
  | pwsh.exe -NoProfile -NonInteractive -File '<windows-skill-path>\\scripts\\windows-helper.ps1'
```

The helper's result is sanitized and never echoes the message or topic. The
skill path must be resolved to the Windows checkout; WSL must not write
`.task-complete-notify` directly. If a WSL process does not inherit the active
session's `CODEX_HOME`, registration fails rather than selecting another home.

When the Stop-hook canary is not viable, set `TASK_COMPLETE_NOTIFY_WATCHER=1` in the Windows environment before arming. The Windows helper starts the hidden `codex-watcher.ps1` fallback and the watcher owns an OS-lifetime lock, persistent per-thread rollout offsets, and the same Stop/claim path. If the environment variable is not set, the watcher can be started explicitly with:

```powershell
pwsh.exe -NoProfile -NonInteractive -File "<skill-dir>\scripts\codex-watcher.ps1"
```

The fallback is detector-only, not a retry worker: it exits after all active requests are consumed and never resends an `attempting` generation.

## Completion and delivery semantics

The hook claims an `armed` generation atomically as `attempting` before making the HTTP request. It holds the same Windows OS-lifetime per-thread lock used by arm until the request reaches a terminal result. The active generation then becomes `success`, `failure`, or `abandoned` and is no longer eligible for a later completion.

Delivery is one-shot best effort: one application-level send attempt per generation, with no retry, no detached worker, and no automatic resend on the next hook. A final HTTP 200-299 is success; non-2xx, timeout, connection/TLS/DNS error, missing topic, and unknown result are terminal failure. A failure may be silent; the hook must not block or alter the Codex turn. Optional diagnostics must use fixed text and must never include message, topic, URI, prompt, response, repository, or log data.

The ntfy server is fixed at `https://ntfy.sh`. `NTFY_TOPIC` is read from the process environment only at send time; this skill neither sets nor persists it. The production sender puts the notification text in the ntfy message body and omits the title header, because the message body is the only display contract.

## Hook canary

Before enabling the hook, verify with a captured non-production hook input that:

1. `session_id` and `turn_id` are available, the active session's `CODEX_HOME` is inherited, and the transcript's first `session_meta` record matches the session, has `thread_source: "user"`, and has no parent thread.
2. `SubagentStop` is not used and `stop_hook_active` does not cause an early or duplicate send.
3. The hook process can read/write `$CODEX_HOME\.task-complete-notify`, acquire the Windows lock, and inherit `NTFY_TOPIC`.
4. Existing Stop hooks do not request continuation that would make this hook an early-stop detector.
5. A mocked or controlled ntfy result exercises 2xx, non-2xx, timeout, connection error, and result-unknown paths; every path consumes the generation and later Stop input does not resend.

If the Stop hook cannot satisfy these checks, use the JSONL watcher fallback with persistent cursors, periodic rescan, complete-line parsing, and the same pre-send claim and one-shot state semantics. The watcher validates `session_meta` before scanning a rollout, treats `FileSystemWatcher`-style wakeups as optional (the shipped fallback uses periodic rescan), and closes its lifetime lock while holding the coordination lock before exit so a concurrent arm can start a replacement watcher without a lost wake-up.

## Diagnostic scripts

The display-comparison scripts under `scripts/diagnostics/` are manual
diagnostics only. They send intentionally random test values to the configured
topic and are never invoked by the arm, Stop-hook, notifier, or watcher paths.
Run them only when an explicit device-display check is wanted; they require the
process `NTFY_TOPIC` and perform a real ntfy publish.

## Privacy and state

State files are under the resolved `$CODEX_HOME\.task-complete-notify`, outside
the skill checkout. Active requests may contain the explicit message; lock,
attempting, and terminal records must not. Do not put `NTFY_TOPIC`, server
credentials, prompt/response text, thread titles, repository paths, raw arm
input, or ntfy response bodies in state, stdout, stderr, or hook output. The
public Windows arm command accepts `-Message`, so its caller's command line
may contain that value; use the WSL stdin envelope when it must not appear in a
command line. WSL requests and all internal helper/notifier/watcher child
invocations carry the message through stdin and never through child-process
arguments.

The design rationale, rejected alternatives, evidence links, and maintenance
invariants are recorded in [`references/design.md`](references/design.md).

See `references/codex-hooks.json` for a minimal Stop-hook configuration example. The example is documentation only; this skill does not edit the user's Codex configuration automatically.
