@AGENTS.md

## Claude Code Skill compatibility fallback

Claude Code hosts may expose shared Skills through explicit slash invocation
without automatically discovering every Skill from natural-language requests.
Until Issue #75 is completed, use the following host-only fallback for a
matching request family. Read the listed shim, then immediately read the
corresponding Skill `SKILL.md`; the Skill remains the only normative runtime
source. Do not load a shim for an unrelated request. If either path cannot be
resolved, stop and report instead of substituting another contract.

| Request family | Compatibility shim |
| --- | --- |
| Copyable code or text for another agent | `link-targets/agents/guides/agent-output.md` |
| Explicit permission or judgment discovery | `link-targets/agents/guides/approval-request-workflow.md` |
| Creating or editing a Git commit message | `link-targets/agents/guides/commit-message.md` |
| Dispatch, handoff, Evidence child, or session identity | `link-targets/agents/guides/delegation.md` |
| .NET build or test | `link-targets/agents/guides/dotnet-testing.md` |
| Visible external posting | `link-targets/agents/guides/external-posting.md` |
| Git state, diff, ref, lock, or range control | `link-targets/agents/guides/git-operations.md` |
| GitHub service/API Issue, PR, review, or comment | `link-targets/agents/guides/github.md` |
| JSON structure or value extraction | `link-targets/agents/guides/structured-data.md` |
