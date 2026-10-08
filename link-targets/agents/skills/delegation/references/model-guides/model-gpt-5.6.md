# GPT-5.6 caller-side delegation guide

Caller-side reference for adapting a handoff or assessing results from an already selected delegate. It does not select models or reasoning effort, define child policy, or change governing contracts.

## Source metadata

- Official family source: <https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.6>
- Official model sources: <https://developers.openai.com/api/docs/models/gpt-5.6-sol>, <https://developers.openai.com/api/docs/models/gpt-5.6-terra>, and <https://developers.openai.com/api/docs/models/gpt-5.6-luna>
- Retrieved: 2026-10-08
- Covered IDs: `gpt-5.6`, `gpt-5.6-sol`, `gpt-5.6-terra`, and `gpt-5.6-luna`.
- The `gpt-5.6` API alias routes to `gpt-5.6-sol`.
- Supported API reasoning effort for the listed models: `none`, `low`, `medium` (default), `high`, `xhigh`, and `max`.

Revalidate the sources before changing this reference. API metadata does not replace host settings or applicable external selections. GPT-5.6 retains one family reference; do not infer GPT-6 variant composition for it.

## Caller adjustments

- Favor lean handoffs: omit duplicated instructions and examples while retaining the governing role contract and required task context.
- Specify the necessary completeness and evidence in the return contract when the model's concise default would leave integration gaps.
- Compare handoff changes on representative tasks using quality and completeness as well as token usage, latency, and cost.
