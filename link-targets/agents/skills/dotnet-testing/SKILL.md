---
name: dotnet-testing
description: Enforce timeouts and configuration contracts when running a .NET build or test. It will not be triggered by unrelated executions.
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

- Because `dotnet test` tends to time out during the build, in principle, after implementation, run it in two stages: `dotnet build` and `dotnet test --no-build`.
- Match the configurations of build and test; as necessary, specify the same configuration, such as `-c Debug`, for both.
- In principle, set the tool-side timeout for build and test to `300000ms` (5 minutes), an adjustable initial value that takes into account temporary delays due to I/O. It does not replace fixed thresholds or approvals.
- When a VSTest run is suspected of hanging, `dotnet test --blame-hang-timeout <duration>` makes the runner collect a dump, report the hanging test, and terminate the test host and its child processes when the duration elapses. Because it stops the run, use it only in a diagnostic run whose stop condition the user has agreed to, choose the duration below the tool-side timeout as an adjustable value, and record it with the result. Microsoft.Testing.Platform projects do not accept this option; use that platform's own hang diagnostics instead.
- Report the passed/failed/skipped counts from the `dotnet test` summary together with the general command report.
- If the build/test configuration or execution conditions cannot be determined, do not force execution; stop and report.
