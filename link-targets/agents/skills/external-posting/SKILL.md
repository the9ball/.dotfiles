---
name: external-posting
description: Used when posting the text to an external visible location such as an issue, pull request, or review comment. It will not be activated for work that does not involve external posting.
---

# External posting workflow

## Discovery contract

- Host fallback: required

- Positive trigger: Compose or send text to an external location that is visible to other users.
- Negative trigger: Only local verification or internal memo, no body sent externally.
- Conditional dependency: The external operation authorization contract is resolved only when the posting's authorization boundary is needed.
- Failure mode: If the authorization boundary or posting conditions cannot be resolved, do not infer the posting content and stop in a fail-safe manner.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

## Guide

Guidelines for posting text where other users can see it, such as issues, pull requests, and review comments. Read them before creating or submitting a post.

### Handling of local environment information

Unless explicitly instructed by the user, do not include information specific to the local environment in text posted where other users can see it. Targets include:

- Absolute path of local file or directory
- Local repository location
- Temporary files and working directory
- Agent execution environment-specific paths such as sandbox and workspace
- Local environment-dependent information that is not necessary to understand the posted content

If necessary, replace such information with an expression that is meaningful to the recipient, such as a relative path from the repository root.

If it is necessary to include information specific to the local environment to understand, reproduce, or resolve the issue, obtain the user's explicit instruction authorizing that information's inclusion before posting. An affirmative answer to a request identifying the information, its posting destination, and disclosure scope can supply that instruction. If an existing explicit instruction already covers that inclusion, destination, and disclosure scope, do not request the same confirmation again. Merely providing local information does not instruct the agent to publish it.

### Content to create as a user

External postings are materialized within the authorization boundary of `link-targets/agents/skills/external-operation-authorization/SKILL.md`.

For every external publication, the content must be user-provided information and an explicit user instruction must authorize the publication content, destination, and disclosure scope. If user-provided provenance is absent or uncertain, do not publish. All editorial discretion below is subject to these prerequisites.

Subject to those prerequisites, the following can be materialized within the established authorization boundary: confirmed facts, performed work, verification results, faithful summaries of existing judgments, and ordinary writing quality and presentation adjustments. This editorial discretion does not enlarge the authorized target, operation, content, or disclosure scope.

For promises, deadlines, support responsibilities, risk acceptance, legal/compliance/financial/security policies, external evaluations, recommendations, criticism, project policies, priorities, and termination decisions attributed to the user, apply the substantive-addition and confirmation rules in the authorization contract's "Discretion of express delegation" section. New wording for a faithful summary is not itself a new user commitment or judgment.

Include unpublished information, personal experiences, intentions, feelings, or unverified facts only when both conditions hold: the user has supplied the information, and an explicit user instruction authorizes publishing that information to the identified destination and disclosure scope. Supplying the information alone is not publication authorization; publication authorization alone does not supply the information. Do not assume a general instruction to post covers personal or unpublished information merely present in the conversation. An existing explicit instruction covering the information and its publication satisfies the confirmation requirement without a second request.

User-provided information includes information supplied directly by the user and the contents of materials the user explicitly designates as sources. Faithful extraction or summarization of those contents retains that provenance; distinguish it from hypotheses or conclusions independently inferred by the agent. Such independently inferred, unverified hypotheses or conclusions are not user-provided information unless the user explicitly adopts them. Preserve their source, attribution as agent inference, and uncertainty even after adoption. Adoption does not itself authorize publication or establish factual accuracy.

Designating a material does not authorize publishing all its contents. Neither material designation nor publication permission overrides third-party confidentiality, applicable authority limits, or other independent restrictions. Do not publish content that would violate those restrictions or fall outside the approved content and disclosure boundary.

If user-provided status, adoption, permitted content, destination, disclosure scope, or compliance with applicable restrictions is indeterminate, do not publish; request the clarification needed to resolve that uncertainty.

Publication authorization does not establish factual accuracy. Verify claims as required, preserve their source and uncertainty, and do not present unverified information as confirmed fact.

These content prerequisites do not replace the authorization contract's "Verification just before execution": immediately before publication, that contract requires current evidence of the actual destination and audience access within the approved disclosure scope.

In review findings, do not let the source of a judgment be confused with the user's own expression of intent.
