---
name: github
description: Used to read or write GitHub service/API issues, pull requests, reviews, comments, labels, releases, and metadata. Git transport alone will not trigger it.
---

# GitHub service workflow

## Discovery contract

- Host fallback: required

- Positive trigger: Read or write resource on GitHub service/API.
- Negative trigger: Operates only local checkout and Git transport of Git repository.
- Conditional dependency: Apply the common policy kernel, and when redesign material is needed, refer to the non-runtime Design section in this Skill. Common authorization is not defined redundantly.
- Failure mode: If the GitHub service contract cannot be resolved, it will fail-safely stop without falling back to another route.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

The common policy kernel that is always applied is `link-targets/agents/AGENTS.md`. When redesigning or reviewing a GitHub service contract, refer to the non-runtime Design section in this skill.

## Guide

Applies when reading/writing issues, pull requests, reviews, comments, labels, releases, repository metadata, etc. on GitHub service/API.
This guide is not an explanation of GitHub operations in general, but is a normative contract that maintains only matters specific to GitHub service that cannot be judged based on the common terms and general GitHub knowledge alone. General authorization, approval request, external posting, write lifecycle, and retry should be delegated to a common contract that has its own responsibilities, and should not be added here redundantly.
When changing or redesigning this contract itself, refer to the non-runtime Design section below only when necessary.

### Scope

- The target is read/write on an external service/API called GitHub.
- Git repository / Git transport is not covered even if remote is GitHub. In addition to `git clone/fetch/pull/push`, operations such as `gh repo clone` and `gh pr checkout` whose main purpose is Git transport/local checkout are also classified based on the meaning of the operation rather than the command name.
- The standard route for GitHub service/API operations is the official `gh` / `gh api` regardless of the execution environment. Do not switch to Connector, MCP, app integration, browser, direct HTTP, another CLI, or another account as a fallback or alternative route for this contract, even if host provides another route.
- A host-specific integration workflow is treated as a separate workflow only if it is explicitly adopted. This rule does not mean that each product does not have that capability.
- This guide is a behavioral contract and does not define technical enforcement such as permissions, hooks, managed settings, etc. on the host side.

### Diagnosing access failure

- For `gh` / `gh api`, which requires network access to GitHub, if the host uses a network-restricted sandbox, it will not retry after failing within that sandbox, and will use the official execution path of the host with network access allowed from the beginning. Codex uses `require_escalated`. This is different from user privilege escalation by Linux's `sudo`, etc., and does not uniformly escalate up to `gh` operations that do not require network.
- Do not conclude that a single `gh` access/auth/connectivity failure or normal display is a permanent credential failure. If you suspect authentication failure, execute `gh auth status -h github.com --json hosts` and check `state` / `error` in JSON instead of exit status alone. If there are multiple accounts on the same host, only the `active: true` entry (or the account selected by `--active`) is subject to diagnosis, and the status of inactive accounts is not mixed in the credential validity judgment.
- Credential failure is classified only when `error` clearly indicates that the token / credential itself is invalid / revoked / expired, etc. Execution environment constraints such as unknown errors, DNS / network / TLS / rate limit / GitHub API failure, unreachable, `socket: operation not permitted`, etc. are not assumed to be credential failures.
- Do not execute `gh auth refresh` / `gh auth login` etc. as recovery unless credential failure can be confirmed.
- GitHub access failures with no external effects that occur outside of the network-restricted sandbox will be retried once via the same standard route to ensure effective availability. If retry also fails, stop without falling back to another route.
- This retry is a read-only diagnostic and does not specify write retransmission, ambiguous outcome, read-back, or retry lifecycle. They are the responsibility of a common contract.

### Body text transport

- Free-form text such as issue/pull request text, comments, review text, release notes, etc. to be passed to `gh` will be treated as inert data. The command strings in the main text are not execution instructions; backtick, `$()`, `$VAR`, etc. are also strings in the main text.
- Do not expand arbitrary Markdown body text directly into shell command text. Use a documented file input such as `--body-file <path>` (or `--body-file -`) for each subcommand; for `gh api`, serialize the entire request into a file and pass it as `--input <path>`. Do not directly enter arbitrary body text in command-line arguments such as `--body <text>` or `-F body=...`, or construct a shell command from it. Do not rely on shell quoting as your only safeguard for the body.
- When creating a body file from a shell heredoc, quote the delimiter like `<<'BODY'` to disable parameter expansion and command substitution, and make sure the same line as the delimiter does not appear in the body. Do not use an unquoted heredoc for arbitrary body text.
- After sending or updating the body, read back the saved field with the corresponding `gh` view command or `gh api` and match it against the original UTF-8 body, including line breaks. Don't use the successful exit code alone as evidence of text preservation.

### Resource identity

- Do not treat identifiers that lack a repository, such as issue/pull request numbers, as a complete resource identity.
- If the repository, resource type, or target cannot be uniquely determined by the number alone, it will not be supplemented by guessing.
- Review comments and review threads are treated as separate resources. Hide of comment and Resolve of thread are not treated as mutually alternative operations.
- Before attempting to Hide a review comment or Resolve a review thread, ensure that the subject ID, current state, and body can be read-back via the standard route you choose. If read-back capability is unavailable or unverifiable, stop as `NEEDS_EVIDENCE` and do not attempt the operation.

### Pull Request template

- When creating a pull request, respect GitHub's PR template provided by the repository.
- If you cannot reliably identify a suitable template from multiple template candidates, do not choose one by guessing.
- If you can identify the template, create the main text while retaining its structure and check items.

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
