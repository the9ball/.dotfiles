# GPT-6 Luna model guide

This is reusable model-family guidance. It does not define a role contract or a runtime tier.

## Source metadata

- Official source: <https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-luna>
- Retrieved: 2026-09-23
- Official display name: GPT-6 Luna
- Model ID: `gpt-6-luna`
- Official positioning: efficient, repeatable work at scale and cost-sensitive, high-volume workloads.
- Official reasoning levels: `none`, `low`, `medium`, `high`, `xhigh`, and `max`.
- Scope: the official GPT-6 family guidance, with Luna-specific model identity and reasoning metadata recorded here.

When modifying this guide or reviewing a change to it, revalidate the official source. If the source identity or relevant guidance has changed or cannot be verified, do not finalize the guide change; report the mismatch and update only the authorized plan, source metadata, or issue.

## Scope and precedence

Use this profile only when the orchestrator or a role contract selects GPT-6 Luna. It supplements the normal instruction hierarchy; it never overrides system or orchestrator constraints, explicit user or task instructions, applicable `AGENTS.md` or skill instructions, safety rules, or approval boundaries. When a role contract conflicts with this guide, the role contract wins. Keep runtime tier mapping outside this document.

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
- Absorb new requirements, change course when asked, and keep side questions from losing track of the broader task.

## Inherited instruction context

- Audit accessible `AGENTS.md`, skills, tool descriptions, and repository files for instructions that affect the task.
- Make precedence explicit when inherited instructions overlap; do not silently discard a constraint.
- Treat this guide as a model profile, not as a replacement for the repository's governing instructions.

## Reasoning effort

- The official API guide lists `none`, `low`, `medium`, `high`, `xhigh`, and `max` for GPT-6 Luna; select the setting intentionally.
- Use `medium` as a balanced starting point, `low` for latency-sensitive work, and `high` or `xhigh` when measured quality improves.
- Reserve `max` for the hardest quality-first tasks and compare representative results before changing a stable default.
- Codex runtime availability is authoritative for CLI-only levels; do not infer an unavailable effort from another host or client.

## Testing and verification

- Match verification to the change: run required checks, but do not expand a small documentation change into unrelated test suites.
- Confirm headings, model naming, source metadata, precedence language, and absence of runtime-tier instructions.
- Compare the guide manually with the official source to confirm actionable paraphrasing without long verbatim copying.
- Treat `git diff --check` and the repository's required checks as part of completion.

## Subagent output

- Return the outcome first, followed by changed paths, evidence, validation, and blockers.
- Give the parent enough context to reproduce the conclusion without forwarding hidden reasoning.
- Use clear Markdown and the requested level of detail; avoid recurring filler or unexplained formatting.
