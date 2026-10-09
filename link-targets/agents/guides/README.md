# Task-specific guides and shared contracts

A directory for detailed guidelines to read after skill discovery and shared contracts resolved conditionally by a Skill. The normative runtime contract of the migrated workflow is owned by the `## Guide` section of the corresponding `SKILL.md`, and the Skill must not be structured to load this directory.

The always-applied policy kernel is `~/.dotfiles/link-targets/agents/AGENTS.md`. Keep task-specific detail in the discovery metadata and runtime Guide of the corresponding Skill to preserve progressive disclosure.

The runtime contract of the migrated workflow has the Guide section of the corresponding Skill as its only original. Keep the temporary Claude compatibility shims and host fallback table until Issue #75 establishes the supported-trigger policy and the corresponding Claude evidence. Explicit slash invocation, natural-language discovery, and host-instruction routing are separate paths; success through one does not establish another.

Issue #75 owns retirement of all twelve shims, including both migration waves. Removing a static inventory does not retire these routes or impose natural-language auto-discovery as a universal retirement requirement.

## Placement rules

- The file name should be ASCII kebab-case.
- Shared guides require an actual caller in AGENTS.md, a Skill, or host instructions. An external-only guide instead records its named consumer and purpose in its own maintenance note; navigation does not supply a runtime activation path.
- The normative contract stays inside its Skill. A required Claude fallback has one same-name thin shim pointing to that owner and an actual row in the global host table. Declare `Host fallback: required` in the Skill's Discovery contract. An exemption declares `Host fallback: exempt; <reason>` there and requires an actual direct host/kernel route, without a shim. These declarations govern validation coverage, not permission or activation.
- [`github-cli-without-clone.md`](github-cli-without-clone.md) records GPT-Chat as its external consumer. This is separate from repository runtime activation and from Issue #75 compatibility retirement.
- `*.design.md` is not a copy or change history of the corresponding normative/runtime contract, but a non-normative design companion that includes future options, reconsideration materials/conditions, responsibility boundaries, etc. Normally, it is not loaded at runtime and is referenced only when changing, redesigning, or reviewing the contract of a skill that has companions.
- Do not write content that contradicts AGENTS.md. In case of conflict, AGENTS.md takes precedence.
- On the AGENTS.md side, leave a core that can at least function without reading the files in this directory. Do not create a configuration where the effect is zero if no reading is performed.

## Reference path

- `instruction root` is the root containing the canonical `link-targets/agents` instruction tree. It is independent of a target checkout and does not require Git metadata.
- `work root` refers to the root of the target repository to be changed/reviewed in the current request. The Git target, difference, target identity, and dirty state are not derived from the instruction root, but are fixed separately from the request and current Git state.
- When referencing another file from the body of a shared reference, use a logical relative path based on the instruction root (for example, `link-targets/agents/guides/<name>.md`).
- Do not write `../../` based on the Skill location or host-specific absolute paths in the body of the shared reference. host integration resolves the instruction root at runtime and then uses logical relative paths.
- Strictly resolve the loaded instruction file or Skill entrypoint through every symlink/junction to its existing final file. Enumerate its real ancestors whose last two components are exactly `link-targets/agents` and which contain both `AGENTS.md` and `guides/README.md`. Require exactly one candidate; require the loaded file and both sentinels to remain inside that candidate after real-path resolution. The instruction root is the candidate's grandparent. Stop on a missing, broken, escaping, malformed, or ambiguous location. Never substitute CWD, the work root, `.git`, home defaults, or a machine-specific absolute path. Resolve requested logical paths against this fixed root and verify their existence and real-path containment before reading. The prose is the runtime procedure; tools are only explicitly invoked verification, including under Personal Codex's instruction-reading exception.
- When using an instruction-root relative path as a Markdown link destination, use a file relative destination that can actually be resolved from the link source. If you just want to display the logical path, use code span to avoid creating unresolvable root-relative destinations from nested files. Skill uses its own `## Guide` as the normative source and does not refer to the guide path as the runtime loader.
- Run `python -B link-targets/agents/tools/validate-instructions.py` and `python -B link-targets/agents/tools/test-instructions.py`. The validator derives callers from managed source and checks missing/escaping targets, zero-caller guides, circular read dependencies, discovery contracts, unique shim ownership, host routes, and active use of retired paths. Do not migrate routes with failures.
- References are read dependencies by default. A source-local HTML `reference-kind` annotation may distinguish an existing `manual-navigation` link in this placement index or WSL setup documents, or a `policy-precedence` reference from a Skill to the always-applied kernel. It must name an independently present reference and cannot exempt a runtime loading instruction. Resolve actual dependency cycles instead of excluding them.

## Validation scope

The source inventory starts with shared guides, canonical/root instructions, discovery Skills and their actual Skill callers, Claude host/agent instructions, publication scripts and WSL documentation, then follows referenced Markdown dependencies. Router/shim owner paths and direct host/kernel routes keep discovery coverage independent of the headings under test. Git supplies tracked and non-ignored candidate paths; Git-free fixtures use the same layout. Concrete logical instruction/script paths and all local Markdown destinations are checked; generated host state and the literal `URL` placeholder are outside this static asset inventory. This is a static check, not evidence of host activation. Retirement scanning covers all tracked/candidate source except the history block below and the validator's own test data.

Classification is descriptive, never authorization for activation, model suppression, authority, or safety gates. Model suppression/lazy loading requires explicit capability profiles and comparative experiments; repository, secret, Git and user-change protection remain independent of model conditions.

## Retirement history

Only this bounded block records retired paths. They must be absent and unused in active source; live Claude shims are excluded from retirement until Issue #75.

<!-- retired-paths:start -->
- `link-targets/agents/guides/approval-request-workflow.design.md`
- `link-targets/agents/guides/github.design.md`
- `link-targets/agents/guides/model-gpt-5.6.md`
- `link-targets/agents/guides/model-gpt-6-astra.md`
- `link-targets/agents/guides/model-gpt-6-sol.md`
- `link-targets/agents/guides/model-gpt-6-luna.md`
- `link-targets/agents/reference-map.json`
- `link-targets/agents/tools/validate-reference-map.py`
- `link-targets/agents/tools/test-reference-map.py`
<!-- retired-paths:end -->

<!-- reference-kind: manual-navigation; target: link-targets/agents/AGENTS.md -->
<!-- reference-kind: manual-navigation; target: link-targets/agents/guides/github-cli-without-clone.md -->
