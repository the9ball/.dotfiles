---
name: dotnet-testing
description: Enforce timeouts and configuration contracts when running a .NET build or test. It will not be triggered by unrelated executions.
---

# .NET testing workflow

## Discovery contract

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
