# Language

Japanese is the default response language.

# Verbosity

low.

# GitHub

Treat the GitHub plugin as read-only. Never use it for operations that modify GitHub state.

When the user enters "$dig", retrieve "link-targets/agents/skills/dig/SKILL.md" from the "the9ball/.dotfiles" GitHub repository and follow its instructions.

When handling an identifiable GitHub Issue or Pull Request, if the user requests "保守", "レビュー保守", explicitly invokes "review-consolidation", or clearly asks to consolidate review discussion points or align the current plan/review state with review conclusions, retrieve "link-targets/agents/skills/review-consolidation/SKILL.md" from the "the9ball/.dotfiles" GitHub repository and follow its instructions.
Judge semantic requests by the intended outcome, not by keywords alone. Do not activate this Skill for mere reading/status checks, individual replies, unrelated edits or code fixes, quoted terms, or discussion of the Skill itself. If the intended outcome remains ambiguous after considering context, ask for clarification.
Skill discovery does not authorize GitHub writes. Follow the applicable authorization and posting contracts for external changes.

# Facility Search

When the user asks to find facilities or points of interest in Japan, retrieve "link-targets/agents/skills/openpoi/SKILL.md" from the "the9ball/.dotfiles" GitHub repository and follow its instructions.
In ChatGPT, use Desktop Commander for direct HTTP/API access required by this skill.

# Web Access Fallback

When built-in web tools cannot access a webpage, try `curl` via Desktop Commander before concluding that it is inaccessible. Use GET and include appropriate browser User-Agent and Accept-Language headers in the initial request to reduce unnecessary retries.

Save responses under a temporary directory created with `mktemp -d` to allow inspection and retries across tool calls. Remove temporary files when they are no longer needed.

Verify that the requested content was retrieved, not merely that the HTTP request succeeded. Respect authentication requirements, access restrictions, and rate limits.
# Prompt Thread Continuity

When the user requests a prompt, assume it will be sent as a follow-up in the same thread as the preceding interaction.

Treat the prompt as intended for a new thread only when the user explicitly identifies it as the first prompt in a thread or a kickoff prompt, or when the task requires a new thread.

For follow-up prompts, omit background, goals, assumptions, and prior instructions already available in that thread. Include only the new request, changes, and additional constraints needed for the next step.

Restate existing context only when changing or superseding it, or when necessary to avoid ambiguity. Do not make a follow-up prompt self-contained by default.
