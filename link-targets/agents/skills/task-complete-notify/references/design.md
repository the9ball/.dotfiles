# Codex turn notifications: design record

The runtime contract is in [SKILL.md](../SKILL.md).
<!-- reference-kind: owner-precedence; target: link-targets/agents/skills/task-complete-notify/SKILL.md -->

## Decision

[Issue #251](https://github.com/the9ball/.dotfiles/issues/251) replaces the thread reservation workflow from [Issue #3](https://github.com/the9ball/.dotfiles/issues/3) with:
Codex Stop → PowerShell → ntfy.sh.
Duplicates and notification volume are accepted. There is no deduplication or delivery guarantee.

The original sender's fixed HTTPS endpoint, environment topic, 2xx check, redirect prohibition, and sanitized failure handling remain useful.
Its variable-message envelope and layered child processes are unnecessary.
HttpClient replaces Invoke-WebRequest to give the request a single total deadline without adding a watchdog child process.
ResponseHeadersRead avoids fetching or logging a response body.
The 20-second hook timeout also bounds runtime startup.

Reservations, UUID extraction/ownership, TTL, locks, terminal state, JSONL scanning, checkpoints, arm/cancel commands, and random-message/title diagnostics are removed.
No compatibility shim is retained: it would imply that the old reservation API still works.
The skill directory and Stop script path remain stable for existing registrations.

No hook-input parser remains. The entry point drains redirected stdin to Stream.Null asynchronously without retaining its content: a local 1 MiB dummy-input check reproduced parent-side broken pipe when the hook exited without reading. The drain starts concurrently with HTTP delivery, which does not depend on EOF or drain success. After delivery, draining gets at most one more second; a pipe still open at process exit is closed by the process. This keeps large input moving while bounding a producer that never closes its pipe. Dot-sourced function callers omit input unless they deliberately supply a stream, so tests never consume their runner's stdin. This is transport handling, not identity validation or state management. Event selection belongs to the Stop registration, not an inferred transcript source.
Other hooks may continue the turn, producing more Stop invocations and notifications; this sender emits no continuation decision.
It must not also be registered as SubagentStop. Interrupted turns have no separate notification registration.

## Evidence and uncertainty

- [Official hook documentation](https://learn.chatgpt.com/docs/hooks) describes concurrent matching hooks, additive sources, hook trust, Stop continuation, and Windows command overrides. The example uses only Stop and an empty JSON response.
- [Issue #3's 2026-09-11 canary](https://github.com/the9ball/.dotfiles/issues/3#issuecomment-5633214614) observed a real CLI Stop, inherited CODEX_HOME/NTFY_TOPIC, and a successful non-publishing HEAD request. It did not establish delivery in every current permission profile.
- At the start of this change, the inspected Windows user-home hooks.json files contained PreToolUse but no Stop entry. This establishes missing registration in those files, not absence of hooks in every other source or the cause of all historical failures.
- The old hook required valid identity fields and a helper process, then depended on same-home session metadata, reservation state, locks, and another notifier process. Those are possible failure points; no trace establishes which caused past lost notifications.
- The tracked permission profiles restrict networking. Actual hook enforcement and inherited sandbox/proxy settings must be checked in the target environment; the sender never removes those variables.
- Native WSL PowerShell avoids cross-OS topic and path translation. It requires an installed Linux PowerShell 7.4+. This is a deployment prerequisite, not an automatic dependency installation.
- Hook configuration remains opt-in to avoid silently beginning external transmission. Merge and trust the example in each actual Codex home. Do not apply production settings as part of offline tests.

## Validation boundary

The offline suite checks all 2xx boundaries, redirects/non-2xx, missing/invalid topics, cancellation by a real HttpClient deadline against an in-memory delayed handler, transport exceptions, fixed request content, no extra headers, generic output, repeated calls without state, and independent process cases for normal input, a pipe held open without EOF, and 1 MiB input. Process tests allow 30 seconds for cold startup and bound asynchronous writes as well as exit. Home-isolation checks use unique absolute temporary paths.
These tests do not establish real ntfy delivery, current Codex lifecycle dispatch, device display, every permission profile, or WSL operation when native PowerShell is unavailable.
Keep those limits explicit in the implementation/PR verification record.

The WSL hooks source uses the same modify template as both Windows homes, preserving unrelated Stop handlers instead of replacing the whole file. Isolated chezmoi tests render Linux and Windows dummy environments and verify Stop preservation, a single managed auth handler, and byte-stable reapplication for all three homes. No production chezmoi apply is performed by these tests.

## Claude Code

Claude Code reuses the same script through `-Source Claude`, which changes only the fixed body to `Claude turn finished`. The parameter accepts exactly `Codex` or `Claude`, case-sensitively, so no caller-supplied text reaches the message. The default stays `Codex`, keeping the existing Codex command strings, and therefore their trust hashes, unchanged. The script path keeps its Codex name for the same reason.
Like Codex, the Claude Code registration is a manual merge of [the example](claude-settings.json) into `~/.claude/settings.json`; chezmoi does not register it. This keeps hook configuration opt-in, so applying dotfiles never silently begins external transmission.
The example path uses forward slashes so that the command parses in both Git Bash and PowerShell, either of which Claude Code may use to run hooks on Windows. Offline tests check both fixed bodies, rejection of other values, a process run with `-Source Claude`, and the Stop-only example; they do not establish Claude Code lifecycle dispatch or real delivery.
