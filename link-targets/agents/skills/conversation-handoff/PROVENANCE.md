# Provenance

## Origin

- Source: https://gist.github.com/tegnike/09dbb98711d8b91e66de21611f5b88ff
- Upstream revision: `f0d01154a869aeb4d6ad2a0a15b7183ab764a0a6`
- Retrieved: 2026-07-16

## License

- License: MIT License
- Copyright: Copyright (c) 2026 tegnike
- License text: `LICENSE`

## Local fork

This skill is maintained as a local, cross-host fork.

Changes from upstream:

- Renamed the skill from `handoff` to `conversation-handoff`.
- Reworked the core instructions to use host-neutral conversation terminology.
- Split host-specific behavior into `references/codex.md` and `references/claude-code.md`.
- Required Codex to use `create_thread` rather than `handoff_thread` or a transcript-preserving fork.
- Added a Claude Code adapter with a manual fallback when no user-visible session creation capability exists.
- Changed the temporary Markdown backup into transient staging that is deleted after both success and failure.
- Updated the Codex UI metadata for the renamed skill.

## Update policy

Upstream changes are reviewed and merged manually.
