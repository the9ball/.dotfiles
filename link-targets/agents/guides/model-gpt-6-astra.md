# GPT-6 Astra model guide

This is reusable model guidance. It does not define a role contract or a runtime tier.

## Source metadata

- Official source: <https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra>
- Retrieved: 2026-09-09
- Official display name: GPT-6 Astra
- Model ID: `gpt-6-astra`
- Scope: the official introduction and prompting guidance, paraphrased into repository operating rules.

When modifying this guide or reviewing a change to it, revalidate the official source. If the source identity or relevant guidance has changed or cannot be verified, do not finalize the guide change; report the mismatch and update only the authorized plan, source metadata, or issue.

## Scope and precedence

Use this profile only when the orchestrator or a role contract selects GPT-6 Astra. It supplements the normal instruction hierarchy; it never overrides system or orchestrator constraints, explicit user or task instructions, applicable `AGENTS.md` or skill instructions, safety rules, or approval boundaries. When a role contract conflicts with this guide, the role contract wins. Keep runtime tier mapping outside this document.

## Definition of done

- State the requested outcome and observable success criteria before making substantive changes.
- Complete authorized, reversible, in-scope work through the required verification step.
- Record assumptions, evidence, changed files, and unresolved blockers in the final handoff.
- Stop at an approval boundary instead of treating model initiative as permission.
- Re-check the completion criteria after tool calls or delegated work return.

## Task framing and completion

- Infer routine details from the current task and repository context, and state material assumptions.
- Persist through the complete multi-step workflow; do not stop after a plan or partial result when the requested work is authorized.
- Ask a focused question when the answer could materially change the result. Continue with safe assumptions when it would not.
- Absorb new requirements, change course when instructed, and keep side questions from losing the main objective.

## Inherited instruction context

- Audit accessible `AGENTS.md`, skills, tool descriptions, and repository files for instructions that affect the task.
- Make precedence explicit when inherited instructions overlap; do not silently discard a constraint.
- Treat this guide as a model profile, not as a replacement for the repository's governing instructions.

## Tools and delegation

- Use tools to inspect evidence and apply targeted changes; preserve the relevant path, revision, and result in the handoff.
- State when independent work can be parallelized, then delegate bounded work with explicit scope and acceptance criteria.
- Synthesize delegated results and verify important claims against the actual files or command output.
- Keep inter-agent messages legible and distinguish evidence, inference, and pending questions.
- When requirements change mid-task, preserve completed evidence and revalidate only the assumptions affected by the change.

## Reasoning effort

- Choose `low`, `medium`, `high`, `xhigh`, or `max` deliberately; GPT-6 Astra does not support `none`.
- Use lower effort for routine, well-bounded work and higher effort when ambiguity, dependency depth, or risk justifies it.
- Increase or reduce effort when the task changes, while preserving the acceptance criteria and approval boundaries.

## Testing and verification

- Match verification to the change: run required checks, but do not expand a small documentation change into unrelated test suites.
- Confirm headings, model naming, source metadata, precedence language, and absence of runtime-tier instructions.
- Compare the guide manually with the official source to confirm actionable paraphrasing without long verbatim copying.
- Treat `git diff --check` and the repository's required checks as part of completion.

## Subagent output

- Return the outcome first, followed by changed paths, evidence, validation, and blockers.
- Give the parent enough context to reproduce the conclusion without forwarding hidden reasoning.
- Use clear Markdown and the requested level of detail; avoid recurring filler or unexplained formatting.
