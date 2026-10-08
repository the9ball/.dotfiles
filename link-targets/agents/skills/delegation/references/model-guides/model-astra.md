# Astra caller-side delegation guide

Caller-side reference for adapting a handoff or assessing results from an already selected delegate. It does not select models or reasoning effort, define child policy, or change governing contracts.

## Source metadata

- Official sources: <https://developers.openai.com/api/docs/models/gpt-6-astra> and <https://developers.openai.com/api/docs/guides/latest-model>
- Retrieved: 2026-10-08
- Covered model: `gpt-6-astra`.
- Supported API reasoning effort: `low`, `medium`, `high`, `xhigh`, and `max`.

Revalidate the sources before changing this reference. API support does not replace host settings or external selections; the composition map does not assume Astra will continue in another family.

## Caller adjustments

- Inspect inherited skills and instruction files when unexplained behavior appears: Astra can be particularly sensitive to instructions already in context.
- State when the delegated workflow needs parallel subagents, within the existing delegation permissions, if the default behavior produces too little delegation.
- Bound the requested verification to the actual task when small changes trigger excessive testing.
- Specify concise output when Astra's tendency toward detailed, formatted responses makes result integration harder.
