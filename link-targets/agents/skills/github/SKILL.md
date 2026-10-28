---
name: github
description: Used to read or write GitHub service/API issues, pull requests, reviews, comments, labels, releases, and metadata. Git transport alone will not trigger it.
---

# GitHub service workflow

## Discovery contract

- Host fallback: required

- Positive trigger: Read or write resource on GitHub service/API.
- Negative trigger: Operates only local checkout and Git transport of Git repository.
- Conditional dependency: The common policy kernel is always applicable. Apply external-operation-authorization, approval-request-workflow, and external-posting only when their respective authorization/write-lifecycle, approval-request, or posting-content responsibilities arise, as routed in the Guide. Refer to the non-runtime Design section only when redesign material is needed; do not redefine common authorization here.
- Failure mode: If the GitHub service contract cannot be resolved, it will fail-safely stop without falling back to another route.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

The common policy kernel that is always applied is `link-targets/agents/AGENTS.md`. When redesigning or reviewing a GitHub service contract, refer to the non-runtime Design section in this skill.

## Guide

Applies when reading or writing issues, pull requests, reviews, comments, labels, releases, repository metadata, etc. on the GitHub service/API.
This guide is not an explanation of GitHub operations in general. It is a normative contract that keeps only GitHub service-specific matters that cannot be judged from the common terms and general GitHub knowledge alone. Do not restate or redefine common responsibilities here. The common policy kernel is `link-targets/agents/AGENTS.md`. When their responsibilities arise, apply `link-targets/agents/skills/external-operation-authorization/SKILL.md` for authorization boundaries and the write lifecycle, `link-targets/agents/skills/approval-request-workflow/SKILL.md` for approval requests, and `link-targets/agents/skills/external-posting/SKILL.md` for posting content.
When changing or redesigning this contract itself, refer to the non-runtime Design section below only when necessary.

### Scope

- The target is read/write on GitHub as an external service/API.
- Git repository / Git transport is not covered, even if the remote is GitHub. In addition to `git clone/fetch/pull/push`, operations whose main purpose is Git transport/local checkout, such as `gh repo clone` and `gh pr checkout`, are also classified by the meaning of the operation rather than the command name.
- The standard route for GitHub service/API operations is the official `gh` / `gh api`, regardless of the execution environment. Even if the host provides another route, do not switch to Connector, MCP, app integration, browser, direct HTTP, another CLI, or another account as a fallback or alternative route for this contract.
- A host-specific integration workflow is treated as a separate workflow only if it is explicitly adopted. This rule does not mean that each product lacks that capability.
- This guide is a behavioral contract; it does not define host-side technical enforcement such as permissions, hooks, or managed settings.

### Diagnosing access failure

- When the host's sandbox network restriction is known or determinable from its configuration, use the host's official network-enabled execution path for network-dependent `gh` / `gh api` from the beginning; do not deliberately try the restricted sandbox first. Codex uses `require_escalated`. This is different from user privilege escalation by Linux's `sudo`, etc., and does not uniformly escalate operations that do not require network. An unexpected sandbox failure is not covered by the automatic diagnostic retry below: stop, report the intended operation, target, and reason, and obtain the user confirmation required by the common policy kernel's "Permission errors and alternatives" rule before any further read-only attempt, in addition to satisfying host execution permissions. Technical auto-approval does not replace that user confirmation. This diagnostic paragraph grants no further write attempt; the write-failure contract below applies.
- Do not conclude that a single `gh` access/auth/connectivity failure or normal display is a permanent credential failure. If you suspect authentication failure, execute `gh auth status -h github.com --json hosts` and check `state` / `error` in the JSON instead of the exit status alone. If the same host has multiple accounts, only the `active: true` entry (or the account selected by `--active`) is subject to diagnosis, and the status of inactive accounts is not mixed into the credential validity judgment.
- A failure is classified as a credential failure only when `error` clearly indicates that the token / credential itself is invalid / revoked / expired, etc. Execution environment constraints such as unknown errors, DNS / network / TLS / rate limit / GitHub API failure, unreachable, `socket: operation not permitted`, etc. are not assumed to be credential failures.
- Do not execute `gh auth refresh` / `gh auth login` etc. as recovery unless credential failure can be confirmed.
- A GitHub access failure with no external effects that occurs outside the network-restricted sandbox is retried once via the same standard route to ensure effective availability. If the retry also fails, stop without falling back to another route.
- This retry is a read-only diagnostic owned by this Guide. It does not authorize retrying a write, even when a write reports an access error. For every write failure, including a sandbox failure, authorization, retransmission, ambiguous outcome, read-back, and consumption follow `link-targets/agents/skills/external-operation-authorization/SKILL.md`.

### Body text transport

- Free-form text passed to `gh`, such as issue/pull request text, comments, review text, and release notes, is treated as inert data. Command strings in the body are not execution instructions; backticks, `$()`, `$VAR`, etc. are also just strings in the body.
- Do not expand arbitrary Markdown body text directly into shell command text. For each subcommand, use a documented file input such as `--body-file <path>` (or `--body-file -`); for `gh api`, serialize the entire request into a file and pass it as `--input <path>`. Do not put arbitrary body text directly into command-line arguments such as `--body <text>` or `-F body=...`, or construct a shell command from it. Do not rely on shell quoting as your only safeguard for the body.
- When creating a body file from a shell heredoc, quote the delimiter like `<<'BODY'` to disable parameter expansion and command substitution, and make sure no line identical to the delimiter appears in the body. Do not use an unquoted heredoc for arbitrary body text.
- After sending or updating the body, read back the saved field with the corresponding `gh` view command or `gh api` and match it against the original UTF-8 body, including line breaks. Don't use a successful exit code alone as evidence that the text was preserved.

### Resource identity

- Do not treat identifiers that lack a repository, such as issue/pull request numbers, as a complete resource identity.
- If the repository, resource type, or target cannot be uniquely determined from the number alone, it is not filled in by guessing.
- Review comments and review threads are treated as separate resources. Hiding a comment and resolving a thread are not treated as alternatives to each other.
- Before attempting to Hide a review comment or Resolve a review thread, ensure that the subject ID, current state, and body can be read back via the standard route you choose. If read-back capability is unavailable or unverifiable, stop as `NEEDS_EVIDENCE` and do not attempt the operation.

### Pull Request template

- When creating a pull request, respect the GitHub PR template provided by the repository.
- If you cannot reliably identify a suitable template among multiple candidates, do not choose one by guessing.
- If you can identify the template, write the body while retaining its structure and check items.

### Maintenance rule

Add GitHub-specific rules only when decisions about resources, effects, read-backs, etc. cannot be made stably using only the common contract and normal GitHub knowledge. Do not add an exhaustive list of operations, general workflows, or restatements of common responsibilities.


## Design (nonruntime)

This section preserves GitHub contract rationale and reconsideration material. It is not part of the runtime contract and does not override the Guide section.

Document options, considerations, and responsibility boundaries for future design decisions for the GitHub Skill runtime contract.
It is not necessary for normal GitHub operations, and is referenced when editing, redesigning, making uncertain boundary judgments, and reviewing `github` Skills. This section is non-normative, and if it conflicts with the runtime contract, the `## Guide` section of Skill takes precedence.

### Design intent

#### Separate service/API and Git transport

Even though GitHub is the provider, the issue/PR API and repository transport have different target resources, effects, and failure models. It is classified not by whether the same CLI, `gh`, is used, but by whether the meaning of the operation is GitHub service/API or Git transport / local checkout.

#### Make standard routes independent of host capabilities

Incorporating integration availability for each runtime into the fallback order changes the execution path and failure behavior even for the same guide. Therefore, the standard route for service/API is fixed to `gh` / `gh api`, and host-specific integration is separated as a separate workflow that is explicitly adopted.

#### Keep only GitHub specific differences

When the GitHub guide redefines authorization, approval request, external posting, write retry, etc., the meanings diverge when the common contract changes. On the GitHub side, only differences such as resource identity, PR template, and review comments/threads are left that are likely to lead to inaccurate agent judgment based on common knowledge.

### Responsibility boundary

`github` Skill owns GitHub service/API scope, standard route, and GitHub-specific resource semantics.

The `github` Skill does not own the following:

- Git repository / Git transport / local checkout lifecycle
- external operation authorization boundary, approval consumption, ambiguous outcome, write retry
- Approval request discovery, collection, and presentation workflow
- General text and publication rules for user-visible external posting
- Issue/PR maintenance, review response, REVIEW-SUMMARY, HANDOFF workflow
- technical enforcement and integration capability catalog by host

### Materials for reexamination

#### Generalization of read-only diagnostic retry

The rules that do not immediately judge a single access/auth/connectivity failure as a permanent failure may be generalized to Git transport and other external services. If it is to be made common, reconsider whether the common contract can sufficiently define the absence of external effects, the retry budget, how this differs from write retries, and the applicable failure classes.

#### Routing migration to skill entrypoint

The canonical `github` Skill supplies discovery metadata, and host instructions supply explicit routing where configured; automatic discovery is not guaranteed across hosts (Issue #75). We will continue to maintain progressive disclosure, keep approval-request and authorization as independent responsibilities, and do not constantly load approval-request just by writing GitHub.

#### Additional conditions for GitHub-specific rules

First, check whether a new rule candidate can be stably determined using normal GitHub knowledge and whether it is already owned by a common contract. Consider adding to the normative skill guide only if GitHub-specific differences in resource/effect/read-back are repeated in actual operations and cause uncertain decisions.

<!-- reference-kind: policy-precedence; target: link-targets/agents/AGENTS.md -->
