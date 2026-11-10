---
name: task-complete-notify
description: Configure or troubleshoot fixed ntfy notifications for every Codex Stop event on Windows or WSL.
---

# Codex turn notifications

A trusted Codex Stop hook runs [the PowerShell script](scripts/codex-stop-hook.ps1) once per invocation, without any reservation.
It sends only `Codex turn finished` to `https://ntfy.sh` using the process environment's `NTFY_TOPIC`.
Do not run it against a real topic for testing without authorization for that publish.

## Setup

1. Make PowerShell 7.4 or newer available as `pwsh.exe` on Windows or native Linux `pwsh` on WSL.
2. Merge the `Stop` entry from [the hook example](references/codex-hooks.json) into `hooks.json` in the active Codex home (`CODEX_HOME`, or the default home when unset). Preserve existing hooks. Replace the example script paths with quoted absolute paths for that execution host.
3. Ensure `NTFY_TOPIC` is inherited by Codex from its launcher. The topic must be 1–64 ASCII letters, digits, underscores, or hyphens. Never print or persist its value. Restart Codex after changing its launch environment.
4. Review and trust the hook through `/hooks` or the desktop hook settings. Verify hooks are enabled and not excluded by managed policy.

Setup is an explicit configuration change; this skill does not install, trust, or enable hooks automatically.
The checked-in chezmoi templates manage the GitHub authentication hook, not this notification hook.
Do not overwrite their output wholesale. The modify templates for .codex, .codex-personal, and .codex-wsl preserve separately installed Stop entries when chezmoi is reapplied.

## Runtime contract

- Register only for `Stop`; do not add `SubagentStop`, `Interrupt`, or a second sender through `notify`. All Stop invocations, including repeated invocations after another hook requests continuation, are eligible. The entry point drains stdin asynchronously without parsing or retaining it, and ignores `stop_hook_active` and all input fields. Delivery starts independently of EOF or drain failures.
- Each invocation makes at most one application HTTP attempt. All 2xx responses succeed; redirects and non-2xx responses fail. There is no retry, watcher, state directory, TTL, UUID lookup, or cancellation API.
- The HTTP client has a 10-second total request timeout. It stops at response headers without reading the body. After delivery, the script waits at most one additional second for input draining, then exits even if the producer keeps stdin open. The synchronous hook example has a 20-second outer timeout covering process startup too.
- The script emits only `{}` and exits 0 on delivery success or failure. It never asks Codex to continue or stop. Failure before PowerShell/script startup and the host's own timeout behavior remain outside the script's control.
- No prompt, answer, thread name, transcript, path, credentials, topic, or response body is sent as message content or written to notification logs/state. The topic is necessarily part of the destination URL seen by ntfy and the network stack.
- Missing or invalid topics quietly skip sending. DNS, TLS, timeout, and HTTP errors are suppressed. Absence of an error is not proof of delivery.

## Windows, WSL, and permissions

Use the same script in each environment; no Windows helper or interop state sharing is needed.
WSL support means native Linux PowerShell. Windows `pwsh.exe` launched from WSL is not a tested delivery path and requires separate environment/path verification.
`CODEX_HOME` affects where Codex loads and trusts hooks, not the script: it never reads Codex data or writes home state.

Keep inherited sandbox, permission, and proxy environment variables unchanged.
Do not strip restrictions or add permissions to make a failed send succeed.
The host must permit the script/runtime to start and HTTPS to ntfy; verify this in the exact target hook environment.
A shell test outside the sandbox does not prove a production hook can connect.

## Migration and verification

Before updating an existing installation, inventory every Codex home (.codex, .codex-personal, and .codex-wsl where used), project hook layers, inline config.toml hooks, managed requirements, enabled plugin hooks, legacy notify senders, and watcher startup registrations.
The stable script path changes old registered senders from reserved-only to every Stop; do not assume a script update causes renewed trust review. With the required configuration authorization, disable or replace obsolete senders and retain one intended Stop registration. Record only safe source labels and handler counts, never topic or raw environment/input data.
Remove obsolete arm/cancel commands and duplicate registrations within that authorized migration.
Old state is inert; do not read, migrate, or delete existing user state automatically.
No script now reads `.task-complete-notify`.

Run `pwsh -NoProfile -NonInteractive -File tests/task-complete-notify.tests.ps1` from this skill directory.
Tests use an in-memory HTTP handler and fake topic; they never publish to ntfy.
For an actual lifecycle canary, keep the topic unset and record only a boolean hook-start marker in an approved temporary directory. Do not record hook input or environment values.
Real delivery requires separate publish authorization.

Read [the design record](references/design.md) when changing this contract or investigating delivery failures.
