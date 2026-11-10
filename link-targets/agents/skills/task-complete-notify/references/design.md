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

No hook-input parser remains. The script drains redirected stdin to Stream.Null without retaining its content: a local 1 MiB dummy-input check reproduced parent-side broken pipe when the hook exited without reading. This transport step lets the host complete its write; it is not identity validation or state management. Event selection belongs to the Stop registration, not an inferred transcript source.
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

The offline suite checks all 2xx boundaries, redirects/non-2xx, missing/invalid topics, cancellation by a real HttpClient deadline against an in-memory delayed handler, transport exceptions, fixed request content, no extra headers, generic output, repeated calls without state, and process exit behavior with 1 MiB input.
These tests do not establish real ntfy delivery, current Codex lifecycle dispatch, device display, every permission profile, or WSL operation when native PowerShell is unavailable.
Keep those limits explicit in the implementation/PR verification record.
