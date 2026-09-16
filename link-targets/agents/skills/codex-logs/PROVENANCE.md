# Provenance

## Origin

- Local implementation: added in this repository by commit `ac9df14676635f920847b5f4d120958edf5fe581` (2026-07-25).
- External reference: OpenAI `codex-plugin-cc` job-state and log layout ([`state.mjs`](https://github.com/openai/codex-plugin-cc/blob/main/plugins/codex/scripts/lib/state.mjs), [`tracked-jobs.mjs`](https://github.com/openai/codex-plugin-cc/blob/main/plugins/codex/scripts/lib/tracked-jobs.mjs)).
- Reference checked: 2026-08-31.

## License

- Local history and public searches did not identify third-party source code copied into this skill.
- The OpenAI repository is a compatibility/reference source, not a bundled dependency. Its source is licensed under the Apache License 2.0 ([`LICENSE`](https://github.com/openai/codex-plugin-cc/blob/main/LICENSE)).
- No separate distribution license is declared for this private local skill.

## Local implementation

This skill is a PowerShell read-only viewer for `codex-companion` job records and logs. It searches the compatible job-data locations, validates the requested job ID, and follows log growth without changing the underlying job.
