# GPT-5.6 model guide

This is reusable model-family guidance. It does not define a role contract or a runtime tier.

## Source metadata

- Official source: <https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.6>
- Retrieved: 2026-09-09
- Official display name: GPT-5.6
- Alias: `gpt-5.6` routes to `gpt-5.6-sol`
- Family coverage: GPT-5.6 family, including Sol, Terra, and Luna.
- Scope: the official GPT-5.6 introduction, prompting, reasoning, and workflow guidance, paraphrased into repository operating rules.

When modifying this guide or reviewing a change to it, revalidate the official source. If the source identity or relevant guidance has changed or cannot be verified, do not finalize the guide change; report the mismatch and update only the authorized plan, source metadata, or issue.

## Scope and precedence

Use this profile when the orchestrator or a role contract selects the GPT-5.6 family. It supplements the normal instruction hierarchy; it never overrides system or orchestrator constraints, explicit user or task instructions, applicable `AGENTS.md` or skill instructions, safety rules, or approval boundaries. When a role contract conflicts with this guide, the role contract wins. Keep runtime tier mapping outside this document.

## Definition of done

- State the user's intended outcome, hard constraints, approval boundary, and observable success criteria.
- Complete safe, authorized, in-scope work through meaningful verification instead of stopping at a plausible draft.
- Report assumptions, evidence, changed files, validation, and unresolved blockers in the final handoff.
- Preserve acceptance criteria even when optimizing for fewer tokens, calls, or turns.

## Task framing and completion

- Infer the underlying goal and expected level of work from context, while retaining domain constraints and explicit success criteria.
- Be proactive and persistent for safe multi-step work; ask when an ambiguity could change the result.
- Continue across tool calls and turns when the task remains authorized and the goal is unchanged.
- Stop before external, destructive, costly, or scope-expanding actions unless the applicable approval is present.

## Inherited instruction context

- Read the applicable `AGENTS.md`, skills, tool descriptions, and repository context before choosing an action.
- Prefer a lean prompt and remove duplicated guidance only when doing so does not remove a mandatory constraint.
- Resolve conflicts explicitly and keep this model profile below the governing instruction hierarchy.

## Tools and delegation

- Use tools deliberately for evidence, edits, and checks; retain the identity of important inputs and outputs.
- Delegate when independent workstreams divide cleanly and the integration cost is justified; otherwise keep the task together.
- Preserve subagent context, acceptance criteria, and evidence when synthesizing delegated results.
- For workflow tuning, compare task success, answer completeness, required evidence, latency, and cost rather than optimizing one metric alone.

## Reasoning effort

- GPT-5.6 supports `none`, `low`, `medium`, `high`, `xhigh`, and `max`; select the setting intentionally.
- Use `medium` as a balanced starting point, `low` for latency-sensitive work, and `high` or `xhigh` when measured quality improves.
- Reserve `max` for the hardest quality-first tasks and compare representative results before changing a stable default.

## Testing and verification

- Validate the result against the user's success criteria and the repository's required checks.
- For workflow or prompt changes, use representative tasks and check completeness and evidence as well as efficiency.
- For documentation changes, verify headings, naming, source metadata, precedence, and the absence of runtime-tier instructions.
- Compare the guide manually with the official source to confirm actionable paraphrasing without long verbatim copying, then run `git diff --check`.

## Subagent output

- Return a concise outcome with paths, evidence, validation, assumptions, and blockers.
- Preserve enough context for the parent to act without exposing hidden reasoning or dropping important caveats.
- Use explicit structure when the caller requests it; GPT-5.6 is concise by default, but completeness takes priority over brevity.
