---
name: codex-rate-limits
description: Read Codex Desktop rate-limit reset times and available reset-credit expirations in Japan time. Use only for an explicit request to inspect Codex usage limits; Windows Codex Desktop only.
---

# Codex-only execution gate

Run this skill only in OpenAI Codex Desktop for Windows. Do not run it in Claude Code, another agent, a CLI, an IDE, or a cloud environment. If you cannot confirm the execution environment, stop.

Do not treat natural-language instructions alone as a security boundary; always run through the included script's own execution-environment check. Do not bypass its guards with `--force`, environment variables, or configuration files.

## Execution

Run the following fixed script only for explicit skill calls.

```powershell
& "$env:USERPROFILE\.agents\skills\codex-rate-limits\scripts\read_codex_rate_limits.ps1"
```

The script searches for the executable Codex Desktop signed bundle `codex.exe`, verifies the Codex home from the skill deployment, and starts the app-server. Do not directly read or modify the parent process's environment variables or authorization files.

The requests that can be sent to the app-server are fixed.

1. `initialize`
2. `initialized` Notification
3. `account/rateLimits/read`

Do not add any RPC methods, arguments, executables, or app-server arguments. Never call reset, consumption, exchange, login, or setting-change operations, including `account/rateLimitResetCredit/consume`.

## Output

Use only the formatted output of the script. The normal usage limit and reset credit are displayed in separate categories.

- Priority is given to `rateLimitsByLimitId` for normal usage quota, otherwise `rateLimits` is used.
- Display both `primary.resetsAt` and `secondary.resetsAt` for each limit in Japan time (JST, UTC+09:00).
- Display `rateLimitResetCredits.availableCount` as total available quantity.
- If `credits` is provided, list each `expiresAt` in Japan time.
- Even if the number of detailed items is less than `availableCount`, only the retrieved details will be displayed and the difference from the total number will be clearly indicated.
- Do not infer values for `null`, empty arrays, missing fields, or invalid times. Use the script's literal output, such as `未提供`, `詳細: 0件`, and `変換不可`.
- Do not display credit ID, account ID, email address, token, raw JSON, or stderr.

## Safety and failure handling

If the bundled Codex Desktop executable cannot be identified, its signature cannot be verified, multiple candidates exist, the `initialize` response `codexHome` does not match the expected value, authentication is required, or the request times out, stop without treating the account lookup as successful. Do not fall back to a standalone CLI on PATH, a downloaded CLI, or a copy of the bundled executable.

Although this skill is read-only, we do not guarantee that nothing will occur, including app-server internal logs and authentication status updates. The skill itself does not output files, cache, or store credentials.

Never run a reset operation, including to check whether reset rights have decreased.
