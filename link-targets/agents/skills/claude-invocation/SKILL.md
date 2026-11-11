---
name: claude-invocation
description: Invoke the Claude Code CLI (`claude --print`) non-interactively from another agent or a script for a review, investigation, or verification, with file-based input and output, a bounded tool set, notification hooks silenced, and streamed results read safely. Not for interactive Claude Code sessions the user drives, for the Claude desktop app, or for plugin-mediated Claude calls.
---

# Claude Code CLI invocation

## Discovery contract

- Host fallback: exempt; shared AGENTS routes agent CLI invocation directly to this Skill

- Positive trigger: Start the Claude Code CLI (`claude --print`) as a non-interactive child process from another agent or a script.
- Negative trigger: Interactive Claude Code sessions, the Claude desktop app, plugin-mediated Claude calls, or merely reading Claude Code settings or logs.
- Conditional dependency: Delegation scope, role independence, and review read scope stay with `delegation` and `advisor-review` when those apply; this Skill owns only how the CLI is started and how its output is read.
- Failure mode: If authentication, the invocation form, or the final result cannot be confirmed, stop and report the call as incomplete; never treat it as passed and never fall back silently to another CLI, account, or authentication route.

## Runtime contract

The shared instructions route Claude Code CLI invocation here directly. Read the Guide before starting the CLI and keep it through reading the result. Host instructions may name a host-local memo with facts confirmed on that host and with the user's standing approvals; read it as well when they do. Such a memo supplements this Guide and does not relax it.

## Guide

The examples use Windows PowerShell and `Start-Process`. The rules apply on any OS; translate the redirections for other shells. For the meaning of each flag, see the [CLI reference](https://code.claude.com/docs/en/cli-reference); for subagent independence and tool limits, see [Subagents](https://code.claude.com/docs/en/sub-agents). These forms were checked against the official documentation and CLI help, which does not by itself prove they work on every host.

### Before starting

- Fix the purpose, the target repository, the read scope, and the forbidden operations before the call, and write them into the request.
- Run `claude auth status` and confirm `loggedIn: true` and the authentication method in use. If it is not logged in, do not log in, switch accounts, or fall back to another CLI or API; ask the user.
- Do not use `--bare`. It reads neither the keychain nor OAuth and accepts only `ANTHROPIC_API_KEY` or `apiKeyHelper`, so a logged-in user still gets `Not logged in`.
- Send only the fixed target and the material needed to judge it, such as identified public Issue or PR text, the local diff, and related code and rules. Never send credentials, private conversations, internal logs, or unrelated local files. Even when the whole repository may be read, do not collect information the judgment does not need.
- Leave model and reasoning effort unset unless the task explicitly selects them.

### Review of supplied material only

When the request contains everything to judge and needs no further reading, disable every tool:

```powershell
$ClaudeProcess = Start-Process -FilePath (Get-Command claude).Source `
  -ArgumentList '--safe-mode --no-session-persistence --permission-mode plan --permission-prompts none --disallowedTools * --output-format stream-json --verbose --print' `
  -RedirectStandardInput $ClaudeRequestFile `
  -RedirectStandardOutput $ClaudeResponseFile `
  -RedirectStandardError $ClaudeErrorFile `
  -NoNewWindow -Wait -PassThru
$ClaudeExitCode = $ClaudeProcess.ExitCode
```

- `--safe-mode` loads no customizations such as `CLAUDE.md`, plugins, or hooks, and keeps the normal authentication route.
- `--disallowedTools "*"` removes every built-in and MCP tool.
- `--permission-mode plan` and `--permission-prompts none` make the call plan-only and read-only.
- `--no-session-persistence` does not save the session.
- `--output-format stream-json --verbose` streams events as JSON Lines so the call can be observed while it runs. Do not use `--output-format json`, which prints everything only at the end.
- `Start-Process -Wait` waits for the CLI without a timeout of its own.

### Autonomous read-only investigation

When Claude needs to read more than the request contains, keep the form above but replace `--disallowedTools *` with `--tools "Read,Grep,Glob,Agent" --disallowedTools "mcp__*"`, which limits Claude to reading tools and child agents.

- `--tools` sets which built-in tools exist; `--allowedTools` sets which operations run without approval. Do not treat them as the same.
- When the investigation must run commands, such as getting a Git diff, add `Bash` to `--tools` and list only the needed read-only operations in `--allowedTools`. Do not allow broad patterns such as `Bash(git *)`, which include changing operations, and do not disable permission checks. `plan` mode is not an OS-level read-only sandbox, so state the no-change rule and the read scope to child agents as well.
- Builds and tests can write artifacts, so do not allow them as read-only commands without checking that the task authorizes them.
- Use child agents only when the task and the host's delegation rules allow them. When a separate phase needs independence, start a new non-fork context and do not pass the parent's conversation or another phase's findings as initial input.
- `--safe-mode` also disables custom Skills and agents. When a check needs them, choose a session-limited launch method from the official documentation and keep any needed settings in the call's temporary directory; never change existing settings automatically.
- When a needed feature is unavailable because of the host or a managed policy, report that limit and do not treat the check as passed.

### Silence notification hooks

Claude Code hooks inherit the environment of the process that starts Claude. A notification hook, such as the `Stop` hook of `task-complete-notify` that reads `NTFY_TOPIC`, would notify the user when this child call ends, although the user is not waiting for it. `--safe-mode` already loads no hooks, but not every form uses it, so always remove such variables from the child's environment and restore them in the caller afterwards:

```powershell
$SavedNotificationTopic = $env:NTFY_TOPIC
$env:NTFY_TOPIC = $null
try {
  # Start Claude here with one of the forms above.
}
finally {
  $env:NTFY_TOPIC = $SavedNotificationTopic
}
```

When a hook does run, it finds no topic, sends nothing, and ends successfully. `--include-hook-events` adds hook start and response events to the stream when a check needs to observe them.

### Files and results

- Create one new directory named `claude-invocation-*` directly under the OS temporary directory for each call. Keep the request, output, and standard-error files in it, together with any prompt, session-limited settings, or child-agent definitions the call needs. Pass the prompt from a UTF-8 file with `-RedirectStandardInput` and capture output with `-RedirectStandardOutput`; never put the prompt on the command line or pipe it through a PowerShell string.
- Read standard output as JSON Lines, not as one JSON document, and parse each complete line separately. The last line may still be being written while the call runs; wait until it is complete.
- To read a redirected file while the call runs on Windows, open it with a .NET `FileStream` with read access and `FileShare.ReadWrite`. Do not resolve a sharing conflict by killing the process or by printing the whole log.
- Do not load the full `--verbose` event stream into a chat or model context. Parse it locally and output only file size, event counts and types, and the progress or error fields needed. Skip tool input and output and repeated prompts.
- After the process exits, check the exit code and that the output file exists and is not empty, then take the completion status, error information, and answer text only from the last `type=result` event. A missing final result, an error, or a truncated stream means the call did not finish. When the answer text is long, check its outline first and read the needed parts.
- Intermediate events or a growing file show activity, not completion or success. Switching to `stream-json` does not allow sending further input to a running call.
- After reading the result, delete only the directory this call created, unless the user named a place to keep it. Before deleting it recursively, confirm that its resolved absolute path is that directory under the OS temporary directory. Never use a wildcard that could match another call's directory.
- Creating, updating, and deleting these files needs no separate confirmation only when user instructions grant it, for example a standing approval in the host-local memo. Otherwise follow the normal approval rules. This Skill grants no approval by itself.

### Waiting

- Run the call in the background or keep the process handle so waiting and checking are separate.
- Give the caller a timeout of at least 30 minutes (1800 seconds), and prefer no timeout where that is possible. Do not stop a call only because it has produced no output for a while.
- File-based input and output and the longer wait avoid loss and early termination by shells, terminals, and callers. They do not extend Claude's own context limit.
