---
name: codex-logs
description: Read or follow the append-only log of a Claude Code codex-companion background job by its task or review job ID. Use when explicitly invoked as $codex-logs with a job ID, optionally with -f or --follow for live monitoring.
---

# Codex Logs

Inspect codex-companion job logs without changing the job.

## Arguments

- Require exactly one job ID such as task-mrvkegys-x8g6ik.
- Treat -f or --follow as follow mode.
- Reject missing or ambiguous job IDs instead of guessing.

## Run

Resolve scripts/watch-codex-job-log.ps1 relative to this SKILL.md.

Without follow mode, run:

    pwsh -NoProfile -NonInteractive -File "<skill-dir>\scripts\watch-codex-job-log.ps1" -JobId "<job-id>"

With -f or --follow, run:

    pwsh -NoProfile -NonInteractive -File "<skill-dir>\scripts\watch-codex-job-log.ps1" -JobId "<job-id>" -Follow

Stream the script output verbatim. In follow mode, keep the command attached until the job reaches completed, failed, or cancelled, or until the user stops the watcher.

## Safety

- Perform only read operations on codex-companion job JSON and log files.
- Do not call result, cancel, resume the Codex thread, or send additional instructions.
- Explain that Ctrl+C stops only the watcher; it does not stop the underlying job.
- If the job cannot be found, report the error and ask the user to verify the job ID.
