# Sol variant model guide

This guide owns Sol-specific differences. It is not an alias for a particular model generation and does not apply without a family guide selected by the delegation composition map.

## Source metadata

- Official source: <https://developers.openai.com/api/docs/models/gpt-6-sol>
- Official family source: <https://openai.com/index/introducing-gpt-6-sol-and-luna/>
- Retrieved: 2026-09-23
- Current composed model: `gpt-6-sol`
- Current positioning: built for complex coding and agentic workflows.
- Current reasoning levels: `none`, `low`, `medium` (default), `high`, `xhigh`, and `max`.

Revalidate the official sources before changing this guide. The Sol name is not assumed to continue into another family; the composition map is the authority for which family, if any, uses this variant guide.

## Variant-specific guidance

- Select Sol for demanding coding and agentic work when its capability/cost balance fits the role and task better than the available alternatives.
- Start from the official default `medium` reasoning effort unless the runtime or task contract specifies otherwise.
- Use lower effort for latency- or cost-sensitive bounded work and higher effort when representative results justify the additional reasoning cost.
- Keep host-specific availability authoritative; do not infer a Codex-only effort or feature from API support alone.
