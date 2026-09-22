# Astra variant model guide

This guide owns Astra-specific differences. It is not an alias for a particular model generation and does not apply without a family guide selected by the delegation composition map.

## Source metadata

- Official source: <https://developers.openai.com/api/docs/models/gpt-6-astra>
- Official prompting source: <https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra>
- Retrieved: 2026-09-23
- Current composed model: `gpt-6-astra`
- Current positioning: OpenAI's most capable model, built for the hardest end-to-end work.
- Current reasoning levels: `low`, `medium`, `high`, `xhigh`, and `max`; `none` is not supported.

Revalidate the official sources before changing this guide. Do not assume the Astra name will exist in a future model family; the composition map determines whether this variant guide is used.

## Variant-specific guidance

- Select Astra when the task needs the strongest available end-to-end capability for complex reasoning, coding, computer use, research, or document creation and the applicable role permits it.
- Astra is more likely to ask when additional input could materially change the result. Keep repository clarification and approval contracts authoritative; do not add model-specific permission gates.
- Audit inherited skills and instruction files carefully because Astra can be especially sensitive to instructions in context.
- Tune delegation explicitly when the workflow benefits from parallel subagents; Astra may otherwise delegate less than the harness expects.
- Calibrate verification to the task because Astra can test more broadly than a small coding change requires.
- Choose reasoning effort deliberately. Use lower effort for routine bounded work and increase it for ambiguity, dependency depth, or quality-first work; never request unsupported `none`.
