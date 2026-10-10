# Claude Code compatibility shim: agent-output

This temporary host fallback exists for Issue #75. The normative runtime
contract is `link-targets/agents/skills/agent-output/SKILL.md`. Resolve that
logical path against the instruction root: the directory that contains the real
`link-targets` directory enclosing this shim, after resolving every
symlink/junction. Do not append it to a link that points at
`link-targets/agents` itself, because the logical path already includes
`link-targets/agents`. Read that Skill and apply its `## Guide` section;
this shim defines no runtime rules of its own. If the Skill cannot be
resolved, stop and report.
