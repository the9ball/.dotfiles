# ChatGPT Web custom instructions

The canonical, copy-ready ChatGPT Web custom-instruction text is in [custom-instructions.md](custom-instructions.md).

## Apply or update

1. Open ChatGPT Web settings and find **Personalization → Custom instructions** (UI labels may change).
2. Copy the **entire contents** of `custom-instructions.md` into the custom-instructions field, replacing the prior text.
3. Save the settings and check that the text was retained. Reapply manually whenever the tracked file changes.

ChatGPT Web does not automatically synchronize this repository file with UI settings. The UI may drift from the tracked version. Do not store secrets, access tokens, personal identifiers, or host-specific absolute paths in this file.

This file contains only ChatGPT-specific routing and preferences. Canonical Skill behavior stays in each Skill's `SKILL.md`; shared agent policy stays in `AGENTS.md`. Host-specific Skill availability and activation must be verified separately.
