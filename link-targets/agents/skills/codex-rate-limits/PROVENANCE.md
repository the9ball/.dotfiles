# Provenance

## Origin

- Local implementation: added in this repository by commit `281f110fd96f05f4e9b1bd83e4ded5c5a3b70399` (2026-08-03).
- Protocol reference: the OpenAI Codex app-server [`account/rateLimits/read` specification](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md).
- Same-purpose prior art checked: [`AFrayde01/codex-rate-limits-skill`](https://github.com/AFrayde01/codex-rate-limits-skill), including its [`MIT License`](https://github.com/AFrayde01/codex-rate-limits-skill/blob/main/LICENSE).
- Reference checked: 2026-08-31.

## License

- Local history and public searches did not identify third-party source code copied into this skill.
- The OpenAI protocol reference and the AFrayde01 skill are references, not bundled dependencies. No code from either source was identified in this Windows PowerShell implementation.
- No separate distribution license is declared for this private local skill.

## Local implementation

This skill starts a verified Windows Codex Desktop app-server, sends a fixed read-only JSON-RPC sequence, and renders rate-limit reset times and reset-credit metadata in Japan time.
