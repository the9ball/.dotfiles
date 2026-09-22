# GPT-6 family model guide

This is reusable GPT-6 family guidance. It does not define a role contract, runtime tier, or variant identity.

## Source metadata

- Official family source: <https://openai.com/index/introducing-gpt-6-sol-and-luna/>
- Official prompting source: <https://developers.openai.com/api/docs/guides/latest-model>
- Retrieved: 2026-09-23
- Family coverage: GPT-6 models selected by the delegation composition map.
- Scope: shared operating guidance factored out of GPT-6 variant profiles; variant identity, positioning, and supported reasoning effort stay in the variant guide.

When modifying this guide or reviewing a change to it, revalidate the official sources and the model-specific pages used by each composed variant. If the source identity or relevant guidance has changed or cannot be verified, do not infer future variant names or capabilities.

## Scope and precedence

Use this profile when the delegation composition map selects the GPT-6 family guide. Apply it together with the selected variant guide. It supplements the normal instruction hierarchy; it never overrides system or orchestrator constraints, explicit user or task instructions, applicable `AGENTS.md` or skill instructions, safety rules, or approval boundaries. When a role contract conflicts with this guide, the role contract wins. Keep runtime tier mapping outside this document.

## Definition of done

- State the requested outcome and observable success criteria before making substantive changes.
- Complete authorized, reversible, in-scope work through the required verification step.
- Record assumptions, evidence, changed files, validation, and unresolved blockers in the final handoff.
- Stop at an approval boundary instead of treating model initiative as permission.
- Re-check completion criteria after tool calls or delegated work return.

## Task framing and completion

- Infer routine details from the current task and repository context while preserving explicit constraints and acceptance criteria.
- Persist through the complete authorized multi-step workflow instead of stopping at a plan or plausible partial result.
- Ask a focused question when an unresolved choice could materially change the result; do not manufacture certainty.
- Incorporate new requirements without losing the main objective, and revalidate assumptions affected by the change.

## Inherited instruction context

- Audit applicable `AGENTS.md`, skills, tool descriptions, and repository context before acting.
- Make precedence explicit when inherited instructions overlap; do not silently discard a constraint.
- Treat family and variant guides as model profiles, not replacements for governing repository or role instructions.

## Tools and delegation

- Use tools deliberately for evidence, edits, and checks, retaining the identity of important inputs and outputs.
- Delegate only under the delegation Skill and role contracts; preserve scope, acceptance criteria, and evidence across handoffs.
- Verify important delegated claims against actual files, revisions, or command output before adopting them.

## Testing and verification

- Match verification to the change and run repository-required checks without broadening a small change into unrelated work.
- Verify model naming, source metadata, composition mapping, and precedence language when model guidance changes.
- Compare externally sourced model facts with current official OpenAI documentation rather than inferring them from older repository text.
- Treat `git diff --check` and applicable repository checks as part of completion.

## Subagent output

- Return the outcome first, followed by changed paths, evidence, validation, and blockers.
- Give the parent enough context to reproduce the conclusion without forwarding hidden reasoning.
- Use clear, concise language and distinguish verified facts from inference or unresolved questions.
