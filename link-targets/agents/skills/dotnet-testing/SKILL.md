---
name: dotnet-testing
description: Enforce timeouts, output handling, and configuration contracts when running a .NET build or test. It will not be triggered by unrelated executions.
---

# .NET testing workflow

## Discovery contract

- Host fallback: required

- Positive trigger: Run build or test of a .NET project.
- Negative trigger: Only performs verification other than .NET or provides an explanation without executing any commands.
- Conditional dependency: There is no additional dependency contract.
- Failure mode: If the build/test configuration or execution conditions cannot be determined, do not force execution, stop and report.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

## Guide

Read before running build/test of `.NET`.

- Since `dotnet test` tends to time out during the build, in principle, after implementation, execute it in two stages: `dotnet build` and `dotnet test --no-build`.
- Match the configurations of build and test, and specify the same configuration such as `-c Debug` for both as necessary.
- In principle, the tool-side timeout for build and test is set to `300000ms` (5 minutes) as an adjustable initial value that takes into account temporary delays due to I/O. This is not a replacement for fixed thresholds or approvals.

### Output handling

- Run build and test non-interactively (stdin from the null device, no pager or credential prompt) so that a wait for input fails instead of hanging.
- Write the full output of a long run to a new file under the OS temporary directory (for example `mktemp` or `New-TemporaryFile`), never inside the repository, and keep the exit code of the command itself; a pipeline must not replace it with the exit code of a filter.
- Decide success from the exit code, not from short output or an empty filter result. Read a filtered excerpt with surrounding context, such as failure lines with neighbouring lines or the final lines, and read the relevant range of the original when the cause is not visible.
- Report the command, exit code, passed/failed/skipped counts when available, and the path of the full output. Report a run that did not execute or did not finish as such, never as passed.
- Short output may be read directly; do not create a file for every command.

### Stalls

- When a run may exceed the tool-side timeout, start it in the background with output written as above, and check from time to time whether the process is alive, whether the log is still growing, and its last few lines, instead of streaming the whole log.
- Treat a process that is alive while its log has not grown since the previous check as a possible stall. Report it with the last lines and the log path, and let the user decide whether to stop it; do not stop it only because time has passed. The check interval is an adjustable operational parameter, not a well-founded threshold.
- When a test run is suspected of hanging, `dotnet test --blame-hang-timeout <duration>` can make the runner report the hanging test and collect a dump. Choose the duration below the tool-side timeout as an adjustable value, and record it with the result.
