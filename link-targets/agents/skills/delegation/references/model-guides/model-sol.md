# Sol caller-side delegation guide

Caller-side reference for adapting a handoff or assessing results from an already selected delegate. It does not select models or reasoning effort, define child policy, or change governing contracts.

## Source metadata

- Official sources: <https://developers.openai.com/api/docs/models/gpt-6-sol> and <https://developers.openai.com/api/docs/models/gpt-6.1-sol>
- Retrieved: 2026-10-08
- Composition: both listed IDs use the GPT-6 family reference and this Sol reference.

| Model ID | Official positioning | Supported API reasoning effort |
| --- | --- | --- |
| `gpt-6-sol` | Complex coding and agentic workflows | `none`, `low`, `medium` (default), `high`, `xhigh`, `max` |
| `gpt-6.1-sol` | Complex coding and professional work with near-Astra performance at a lower cost | `low`, `medium` (default), `high`, `xhigh`, `max` |

These API facts do not replace the host's supported settings or applicable external selections. GPT-6.1 Sol does not support API `none` or `minimal`; report an unsupported explicit selection through the delegation contract rather than silently replacing it.

Revalidate the exact model pages before changing this reference. The composition map determines coverage; the Sol name does not imply support for future IDs or families.

## Caller adjustments

- Keep the same handoff guidance for Sol 6 and 6.1 until representative results demonstrate a task-relevant prompting difference.
- Preserve the exact selected model ID when recording evidence or comparing results. Shared guidance does not make the IDs interchangeable or establish equal capabilities.
