---
name: codex-invocation
description: Invoke the Codex CLI (`codex review` or `codex exec`) non-interactively from another agent or a script for a review, investigation, or verification, with network disabled, file-based input and output, notification hooks silenced, and results read safely. Not for running Codex inside WSL (use `wsl-codex-exec`), for plugin-mediated Codex calls such as codex-companion, or for interactive Codex sessions the user drives.
---

# Codex CLI invocation

## Discovery contract

- Host fallback: exempt; shared AGENTS routes agent CLI invocation directly to this Skill

- Positive trigger: Start the Codex CLI (`codex review`, `codex exec`) as a non-interactive child process from another agent or a script.
- Negative trigger: Codex inside WSL (`wsl-codex-exec`), plugin-mediated Codex calls, interactive Codex sessions, or merely reading Codex logs or configuration.
- Conditional dependency: Delegation scope, role independence, and review read scope stay with `delegation` and `advisor-review` when those apply; this Skill owns only how the CLI is started and how its output is read.
- Failure mode: If authentication, the invocation form, or the result cannot be confirmed, stop and report the call as incomplete; never treat it as passed and never fall back silently to another CLI, account, or sandbox mode.

## Runtime contract

The shared instructions route Codex CLI invocation here directly. Read the Guide before starting the CLI and keep it through reading the result. Host instructions may name a host-local memo with facts confirmed on that host and with the user's standing approvals; read it as well when they do. Such a memo supplements this Guide and does not relax it.

## Guide

The examples use Windows PowerShell and `Start-Process`. The rules apply on any OS; translate the redirections for other shells.

### Before starting

- Fix the purpose, the target repository, the read scope, and the forbidden operations before the call, and write them into the request.
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
- Leave model and reasoning effort unset unless the task explicitly selects them.

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

### Files and results

- Create one new directory named `codex-invocation-*` directly under the OS temporary directory for each call, and keep the request, output, standard error, and final-message files in it. Pass the prompt from a UTF-8 file through standard input, never on the command line.
- The output log contains the instructions Codex loaded, such as `AGENTS.md`. Do not read the whole log into a chat or model context, and do not share it outside the machine.
- For `codex review`, the result is the part after the last line that is exactly `codex`. Do not judge success by the exit code: an exit code of 0 that ends with `Review blocked …` is a failed review.
- For `codex exec`, read the `-o` file. A missing or empty file means the call did not finish.
- Intermediate output or a growing file shows activity, not completion or success.
- After reading the result, delete only the directory this call created. Before deleting it recursively, confirm that its resolved absolute path is that directory under the OS temporary directory. Never use a wildcard that could match another call's directory.
- Creating and deleting these files needs no separate confirmation only when user instructions grant it, for example a standing approval in the host-local memo. Otherwise follow the normal approval rules. This Skill grants no approval by itself.

### Waiting

- Run the call in the background, because it can take long.
- Give the caller a timeout of at least 30 minutes (1800 seconds), and prefer no timeout where that is possible. Do not stop a call only because it has produced no output for a while.
