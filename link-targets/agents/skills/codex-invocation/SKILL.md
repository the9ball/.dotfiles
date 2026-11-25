---
name: codex-invocation
description: Invoke the Codex CLI (`codex review` or `codex exec`) non-interactively from another agent or a script for review, investigation, verification, or implementation delegated under a fixed contract, or resume a saved session, with network disabled, file-based input and output, notification hooks silenced, and results read safely. Not for running Codex inside WSL (use `wsl-codex-exec`), for plugin-mediated Codex calls such as codex-companion, or for interactive Codex sessions the user drives.
---

# Codex CLI invocation

## Discovery contract

- Host fallback: exempt; shared AGENTS routes agent CLI invocation directly to this Skill

- Positive trigger: Start the Codex CLI (`codex review`, `codex exec`) as a non-interactive child process from another agent or a script, including implementation delegated under a fixed contract and resuming a saved session (`codex exec resume`).
- Negative trigger: Codex inside WSL (`wsl-codex-exec`), plugin-mediated Codex calls, interactive Codex sessions, or merely reading Codex logs or configuration.
- Conditional dependency: Delegation scope, authority, role independence, and review read scope stay with `delegation`, `execution-lifecycle-gate`, `advisor-review`, and the caller's contract as applicable. This Skill owns only how the CLI is started and how its output is read.
- Failure mode: If authentication, the invocation form, or the result cannot be confirmed, stop and report the call as incomplete; never treat it as passed and never fall back silently to another CLI, account, or sandbox mode.

## Runtime contract

The shared instructions route Codex CLI invocation here directly. Read the Guide before starting the CLI and keep it through reading the result. Host instructions may name a host-local memo with facts confirmed on that host and with the user's standing approvals; read it as well when they do. Such a memo supplements this Guide and does not relax it.

## Guide

The examples use Windows PowerShell and `Start-Process`. The rules apply on any OS; translate the redirections for other shells.

### Before starting

- Fix the purpose, the target repository, the read scope, any permitted edits, and the forbidden operations before the call, and write them into the request.
- Run `codex login status` and confirm that Codex is logged in. If it is not, do not log in, switch accounts, or fall back to another CLI or API; ask the user.
- Send only the fixed target and the material needed to judge it, such as identified public Issue or PR text, the local diff, and related code and rules. Never send credentials, private conversations, internal logs, or unrelated local files.

### Common settings

Always add two settings: one turns off the managed network proxy, and the other turns off network access in the permission profile that the child will actually use. Profiles are selected by name, and the `default_permissions` key of the Codex home's `config.toml` names the active one, so a fixed name such as `default-permissions` only works for a home whose active profile has that name. Resolve the name from the home the child inherits (`CODEX_HOME`, or `~/.codex` when it is unset):

```powershell
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
# A top-level TOML key must come before the first table header, so stop scanning there.
$TopLevelLines = foreach ($ConfigLine in Get-Content -LiteralPath (Join-Path $CodexHome 'config.toml')) {
  if ($ConfigLine -match '^\s*\[') { break }
  $ConfigLine
}
$ProfileMatch = $TopLevelLines |
  Select-String -CaseSensitive -Pattern '^\s*default_permissions\s*=\s*"([A-Za-z0-9_-]+)"\s*$' |
  Select-Object -First 1
if ($null -eq $ProfileMatch) { throw 'No named default_permissions profile; ask the user before starting Codex.' }
$ActiveProfile = $ProfileMatch.Matches[0].Groups[1].Value
$NetworkOffSettings = "-c features.network_proxy=false -c permissions.$ActiveProfile.network.enabled=false"
```

- If the home has no top-level `default_permissions` line or names a built-in profile (one starting with `:`), stop and ask the user instead of guessing. Before the call, also check whether the target repository's `.codex/config.toml` or a managed configuration you can see sets `default_permissions`, and whether the call would pass `-p`; if so, stop and ask as well. Never switch the profile or the sandbox mode to make the setting apply.
- The two settings turn off network access and the managed network proxy for that call only. They only narrow the sandbox, so they need no separate confirmation.
- Where Codex enables sandbox network access, it routes it through managed networking. On Windows that requires the elevated sandbox, which a non-administrator user cannot set up. There every shell command then fails, regardless of whether it uses the network, and `codex review` ends with `Review blocked …` and exit code 0. `-c sandbox_workspace_write.network_access=false` alone does not avoid this.
- When a request needs the network, do not run it with these settings, and do not switch the sandbox mode on your own. Ask the user.
- Never use `--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust`, or `--approve-for-me`.
- Pass `-m <model>` and `-c model_reasoning_effort=<effort>` only for settings the task explicitly selects. A Codex child cannot inherit the caller's model or effort, so in a fresh session an unspecified field uses the Codex home's configured default, which is the runtime default in `delegation` terms. When resuming, pass only explicit selections and leave the session's other settings unchanged.

### Silence notification hooks

Codex hooks inherit the environment of the process that starts Codex. A notification hook, such as the `Stop` hook of `task-complete-notify` that reads `NTFY_TOPIC`, would notify the user when this child call ends, although the user is not waiting for it. Remove such variables from the child's environment and restore them in the caller afterwards:

```powershell
$SavedNotificationTopic = $env:NTFY_TOPIC
$env:NTFY_TOPIC = $null
try {
  # Start Codex here with one of the forms below.
}
finally {
  $env:NTFY_TOPIC = $SavedNotificationTopic
}
```

With `codex exec`, the hook still starts, finds no topic, sends nothing, and ends successfully. Whether hooks run during `codex review` has not been observed; removing the variable keeps a notification hook from sending in either case.

The Japanese reply guard (`~/.agents/hooks/japanese_guard.py --agent codex`), registered as a `Stop` hook in the Windows work and personal homes, sends an English-dominant final answer back to be rewritten in Japanese. A child call's result is read by the caller, not shown to the user, and may need to stay in English, so set `JAPANESE_GUARD_DISABLE=1` in the child's environment only, next to removing `NTFY_TOPIC`, and restore the previous value afterwards:

```powershell
$SavedJapaneseGuardDisable = $env:JAPANESE_GUARD_DISABLE
$env:JAPANESE_GUARD_DISABLE = '1'
try {
  # Start Codex here, inside the NTFY_TOPIC block above.
}
finally {
  $env:JAPANESE_GUARD_DISABLE = $SavedJapaneseGuardDisable
}
```

Other hooks, such as the GitHub authentication gate, keep running; only the guard does nothing.

### Review

```powershell
$CodexProcess = Start-Process -FilePath (Get-Command codex).Source `
  -ArgumentList "review --base origin/master $NetworkOffSettings" `
  -RedirectStandardOutput $CodexResponseFile `
  -RedirectStandardError $CodexErrorFile `
  -NoNewWindow -Wait -PassThru
$CodexExitCode = $CodexProcess.ExitCode
```

- `--base <branch>` reviews the whole branch, `--uncommitted` the uncommitted changes, and `--commit <sha>` one commit.
- `codex review` rejects `--base` together with a prompt argument (exit code 2). To pass review points, use the `codex exec` form instead.

### Investigation and verification

```powershell
$CodexProcess = Start-Process -FilePath (Get-Command codex).Source `
  -ArgumentList "exec --sandbox read-only --ephemeral $NetworkOffSettings -o `"$CodexLastMessageFile`" -" `
  -RedirectStandardInput $CodexRequestFile `
  -RedirectStandardOutput $CodexResponseFile `
  -RedirectStandardError $CodexErrorFile `
  -NoNewWindow -Wait -PassThru
$CodexExitCode = $CodexProcess.ExitCode
```

- `--sandbox read-only` keeps Codex from changing files.
- `--ephemeral` does not save the session.
- `-o <file>` writes only the final message to a separate file.
- The trailing `-` reads the prompt from standard input.

When the request lets Codex delegate to subagents, drop `--ephemeral` and keep every other setting. With `--ephemeral`, spawning a subagent fails with `invalid thread-store request: no rollout found for thread id …`, and some Codex Skills then stop instead of doing the work in the main thread. Without it, the session record, including the request and Codex's output, stays in the Codex home, so keep credentials and private conversations out of the request.

### Implementation

Use this form for implementation delegated under a fixed contract. Use the request file for the approved edit scope and verification requirements.

```powershell
$CodexProcess = Start-Process -FilePath (Get-Command codex).Source `
  -ArgumentList "exec --sandbox workspace-write --json $NetworkOffSettings -C `"$CodexCheckout`" -o `"$CodexLastMessageFile`" -" `
  -RedirectStandardInput $CodexRequestFile `
  -RedirectStandardOutput $CodexResponseFile `
  -RedirectStandardError $CodexErrorFile `
  -NoNewWindow -Wait -PassThru
$CodexExitCode = $CodexProcess.ExitCode
```

- Omit `--ephemeral` when the session may need to be resumed or its effective settings checked later.
- On Windows, `workspace-write` protects `.git` from child writes. For example, `git add` fails to create `index.lock`. The caller handles any Git writes and external operations under its own contract. Both network-off settings still apply.
- In Windows requests, tell the child to use an explicit `.\` path when invoking a script in the working directory, with the required interpreter or runner. The sandbox sets `NoDefaultCurrentDirectoryInExePath`.
- Ask the child to print `$LASTEXITCODE` immediately after each native command whose exact exit code is needed. The child's shell runs commands through `pwsh -Command`, which reports a nonzero native exit code as 1.
- State whether the child must preserve existing line endings. Edits may convert CRLF to LF.

### Resume a saved session

Use the same input and output redirections and hook settings as for implementation. With `Start-Process`, set `-ArgumentList` as shown here for a session using `workspace-write`.

```powershell
"exec --sandbox workspace-write --json -C `"$CodexCheckout`" resume $NetworkOffSettings -o `"$CodexLastMessageFile`" $CodexSessionId -"
```

- `codex exec resume` accepts neither `--sandbox` nor `--cd`. Put `--sandbox`, `--json`, and `-C` before `resume` as `exec` options. Put `-c` settings (including both network-off settings), `-m`, and `-o` after `resume`, using `resume <options> <SESSION_ID> -`. Use the sandbox selected for the task and take the session ID from `thread.started` as described below.
- A fresh session pays a fixed input cost to load shared instructions. Resume a short session for small follow-ups on the same work. Start a fresh session for an independent review or after a long session, because resuming a long session resends its whole context on each model call.

### Files and results

- Create one new directory named `codex-invocation-*` directly under the OS temporary directory for each call, and keep the request, output, standard error, and final-message files in it. Pass the prompt from a UTF-8 file through standard input, never on the command line.
- The output log contains the instructions Codex loaded, such as `AGENTS.md`. Do not read the whole log into a chat or model context, and do not share it outside the machine.
- For `codex review`, the result is the part after the last line that is exactly `codex`. Do not judge success by the exit code: an exit code of 0 that ends with `Review blocked …` is a failed review.
- For `codex exec`, read the `-o` file. A missing or empty file means the call did not finish.
- With `--json`, read the `thread_id` field of `thread.started` as the session ID. When resuming, `turn.completed.usage` is cumulative across the whole session.
- Treat a `turn.failed` or `error` event as an incomplete call. Identify a usage-limit failure by its `turn.failed` message, even if it gives no reset time. Record the reset time or record it as unknown. If the time is known, wait until the reset before retrying. If it is unknown, retry only once the limit is known to have reset or the user decides to retry. Keep the same account, Codex home, and route.
- A child that stops before completion is incomplete. If it ended without the caller or user intending to stop it, for example after a crash, timeout, host interruption, or usage-limit failure, it may be resumed by session ID within the original authority, subject to the reset rule above. A child stopped at the user's instruction may be resumed only on a new instruction from the user.
- Intermediate output or a growing file shows activity, not completion or success.
- After reading the result, delete only the directory this call created. Before deleting it recursively, confirm that its resolved absolute path is that directory under the OS temporary directory. Never use a wildcard that could match another call's directory.
- The user grants standing approval for these temporary-file operations: creating the per-call `codex-invocation-*` directory and the request, output, standard-error, and final-message files in it, and deleting that directory after the result is read under the checks above. They need no separate confirmation, even when the task is otherwise read-only or forbids changing existing files. An explicit instruction that forbids temporary files or asks for per-call approval takes precedence.
- This approval does not cover existing files, the Git index, refs, or history, persistent settings, authentication or permission changes, or external posting, and it does not bypass the host's sandbox, managed policy, or tool approvals.

### Waiting

- Run the call in the background, because it can take long.
- Give the caller a timeout of at least 30 minutes (1800 seconds), and prefer no timeout where that is possible. Do not stop a call only because it has produced no output for a while.
