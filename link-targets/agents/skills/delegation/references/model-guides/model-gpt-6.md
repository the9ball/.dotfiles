# GPT-6 caller-side delegation guide

Caller-side reference for adapting a handoff or assessing results from an already selected delegate. It does not select models or reasoning effort, define child policy, or change governing contracts.

## Source metadata

- Official source: <https://developers.openai.com/api/docs/guides/latest-model>
- Retrieved: 2026-10-08
- Covered models: `gpt-6-astra`, `gpt-6-sol`, `gpt-6.1-sol`, and `gpt-6-luna`, as explicitly mapped by the delegation Skill.
- Scope: family-level handoff calibration; the selected variant reference owns verified model differences.

Revalidate the source before changing this reference. The official family prompting suggestions originate in Astra observations; their suitability for another covered model remains a hypothesis to evaluate on representative tasks.

## Caller adjustments

- Use a shared handoff shape for covered models. Add model-specific wording only when observed results show that it improves the requested outcome.
- Make unresolved choices that require user input distinguishable from routine details the delegate may infer, so stronger initiative does not turn every ambiguity into a pause.
- Specify the required answer length and structure when verbosity affects integration of the delegate's result.
- Evaluate prompt changes using task success, completeness, evidence, latency, and cost. A shared reference does not establish equivalent behavior across models.

Read this together with the mapped variant reference only when a model-specific adjustment is needed. Incorporate relevant task framing into the handoff within the existing scope; do not automatically load these references in the child or copy them wholesale as child instructions.
