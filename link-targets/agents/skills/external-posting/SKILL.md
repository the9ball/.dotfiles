---
name: external-posting
description: Used when posting the text to an external visible location such as an issue, pull request, or review comment. It will not be activated for work that does not involve external posting.
---

# External posting workflow

## Discovery contract

- Positive trigger: Compose or send text to an external location that is visible to other users.
- Negative trigger: Only local verification or internal memo, no body sent externally.
- Conditional dependency: The external operation authorization contract is resolved only when the posting's authorization boundary is needed.
- Failure mode: If the authorization boundary or posting conditions cannot be resolved, do not infer the posting content and stop in a fail-safe manner.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

## Guide

Guidelines for posting text where other users can see it, such as issues, pull requests, and review comments. Read before creating or submitting your post.

### Handling of local environment information

In text posted where other users can see, do not include information specific to the local environment unless explicitly instructed by the user.

Targets include:

- Absolute path of local file or directory
- Local repository location
- Temporary files and working directory
- Agent execution environment-specific paths such as sandbox and workspace
- Local environment-dependent information that is not necessary to understand the posted content

If necessary, replace it with an expression that is meaningful to the recipient, such as a relative path from the repository root.

If we determine that it is necessary to include information specific to the local environment in order to understand, reproduce, or resolve the issue, we will check with the user before posting.

### Content to create as a user

The materialization of external postings is done within the authorization boundary of `link-targets/agents/skills/external-operation-authorization/SKILL.md`.

Confirmed facts, performed work, verification results, faithful summaries of existing judgments, and ordinary writing quality and presentation adjustments can be determined within a semantic range.

Promises, deadlines, support responsibilities, risk acceptance, legal/compliance/financial/security policies, external evaluations, recommendations, criticism, project policies, priorities, and termination decisions need to be confirmed when newly created from the user's perspective.

Do not add unpublished information, personal experiences, intentions, feelings, or unverified facts to your posts unless the user indicates so.

In review findings, do not let the source of a judgment be confused with the user's own expression of intent.
