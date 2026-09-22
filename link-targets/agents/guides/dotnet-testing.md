# Claude Code compatibility shim: dotnet-testing

This temporary host fallback exists for Issue #75. The normative runtime
contract is `link-targets/agents/skills/dotnet-testing/SKILL.md`. Read that
Skill and apply its `## Guide` section; this shim defines no runtime rules of
its own. If the Skill cannot be resolved, stop and report.
