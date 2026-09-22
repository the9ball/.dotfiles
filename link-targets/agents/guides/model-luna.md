# Luna variant model guide

This guide owns Luna-specific differences. It is not an alias for a particular model generation and does not apply without a family guide selected by the delegation composition map.

## Source metadata

- Official source: <https://developers.openai.com/api/docs/models/gpt-6-luna>
- Official family source: <https://openai.com/index/introducing-gpt-6-sol-and-luna/>
- Retrieved: 2026-09-23
- Current composed model: `gpt-6-luna`
- Current positioning: OpenAI's most efficient model for focused, high-volume tasks.
- Current reasoning levels: `none`, `low`, `medium` (default), `high`, `xhigh`, and `max`.

Revalidate the official sources before changing this guide. The Luna name is not assumed to continue into another family; the composition map is the authority for which family, if any, uses this variant guide.

## Variant-specific guidance

- Select Luna for focused, repeatable, high-volume work when the role and acceptance criteria can be met with the more efficient variant.
- Start from the official default `medium` reasoning effort unless the runtime or task contract specifies otherwise.
- Increase effort for harder bounded work only when measured quality warrants it; choose a more capable available model rather than relying on effort alone when task complexity exceeds Luna's intended fit.
- Keep host-specific availability authoritative; do not infer a Codex-only effort or feature from API support alone.
