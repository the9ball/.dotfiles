# Task-specific guides and shared contracts

The five resolver Skills contain self-contained instruction-root resolution; other consumers use the Reference path placement rule. Each migrated Skill owns its runtime contract. This directory holds placement rules and temporary host compatibility shims; a migrated Skill does not load a legacy guide as its runtime contract.

The always-applied policy kernel is `~/.dotfiles/link-targets/agents/AGENTS.md`. Keep task-specific detail in the discovery metadata and runtime Guide of the corresponding Skill to preserve progressive disclosure.

The runtime contract of the migrated workflow has the Guide section of the corresponding Skill as its only original. Keep the temporary Claude compatibility shims and host fallback table until Issue #75 establishes the supported-trigger policy and the corresponding Claude evidence. Explicit slash invocation, natural-language discovery, and host-instruction routing are separate paths; success through one does not establish another.

Issue #75 owns retirement of all twelve shims, including both migration waves. Removing a static inventory does not retire these routes or impose natural-language auto-discovery as a universal retirement requirement.

## Placement rules

- The file name should be ASCII kebab-case.
- Shared guides require an actual dependency from a managed source. An external-only guide instead records its named consumer and purpose in its own maintenance note; navigation does not supply a runtime activation path. The validator currently accepts only `GPT-Chat` in the `> **External consumer:** <name>; purpose: <text>` record, with nonempty purpose; another consumer requires a coordinated validator/test change.
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
- Strictly resolve the loaded instruction file or Skill entrypoint through every symlink/junction to its existing final file. Enumerate its real ancestors whose last two components are exactly `link-targets/agents` and which contain both `AGENTS.md` and `guides/README.md`. Require exactly one candidate; require the loaded file and both sentinels to remain inside that candidate after real-path resolution. The instruction root is the candidate's grandparent. Stop on a missing, broken, escaping, malformed, or ambiguous location. Never substitute CWD, the work root, `.git`, home defaults, or a machine-specific absolute path. Resolve requested logical paths against this fixed root and verify their existence and real-path containment before reading. Each resolver Skill contains its runtime procedure; this section records the placement rule. Tools are only explicitly invoked verification, including under Personal Codex's instruction-reading exception.
- When using an instruction-root relative path as a Markdown link destination, use a file relative destination that can actually be resolved from the link source. If you just want to display the logical path, use code span to avoid creating unresolvable root-relative destinations from nested files. Skill uses its own `## Guide` as the normative source and does not refer to the guide path as the runtime loader.
- Run `python -B link-targets/agents/tools/validate-instructions.py` and `python -B link-targets/agents/tools/test-instructions.py`. The validator derives callers from managed source and checks missing/escaping targets, zero-caller guides, circular read dependencies, discovery contracts, unique shim ownership, host routes, and active use of retired paths. Do not migrate routes with failures.
- References are read dependencies by default. A source-local HTML `reference-kind` annotation may distinguish an existing `manual-navigation` link in this placement index or WSL setup documents, or a `policy-precedence` reference from a Skill to the always-applied kernel. It must name an independently present reference. Resolve actual dependency cycles instead of excluding them.
- An `owner-precedence` annotation is limited to `<skills>/<name>/references/design.md` pointing to that same Skill's `<skills>/<name>/SKILL.md`, with the layout checked after real-path resolution and exactly one independent Markdown owner link. This classifies a design record's ownership reminder, preserves target validation, and does not exempt the Skill's forward reference to the design record.
- Every annotation rejects English loading verbs (`read`, `load`, `apply`, `invoke`, `resolve`, `use`, `follow`, `run`) in statements referencing its target. This lexical guard is not a semantic proof or a Japanese-language loader detector; `see` remains navigational. Added loading behavior requires ordinary review even when the lexical check passes.

## Validation scope

The source inventory starts with every direct canonical `skills/<name>/SKILL.md`, shared guides, canonical/root instructions, Claude host/agent instructions, publication scripts and WSL documentation, then follows referenced local Markdown. All Skill entrypoints receive frontmatter and reference checks, regardless of body markers or inbound routes. Full Discovery/Runtime/Guide and fallback checks apply to shim owners, direct host/kernel routes, and Skills with a discovery-section signal, a `- Host fallback:` bullet anywhere, or generic contract-field bullets before the first Runtime contract/Guide section. Ordinary bullets inside Runtime contract/Guide do not declare participation. Standard Skills without those signals remain valid; source alone cannot infer an unwritten intent to join Issue #75's compatibility set. Production tests preserve the existing twelve required and two exempt profiles and twelve shim routes.

Frontmatter validation is a bounded raw-scalar check, not a general YAML parser. The source reader removes an optional UTF-8 BOM; the decoded text begins with `---` on its first line and closes with another exact, newline-terminated `---` line. Each key is matched at column zero by `^{key}:[ \t]*(.+)$` and must have exactly one matching occurrence. Lines with nothing after the colon are not counted; whitespace-only values count as occurrences and yield an empty scalar, which is rejected. Raw values are stripped; the six exact indicators `>`, `|`, `>-`, `|-`, `>+`, `|+` instead take nonempty indented content after the key line and strip it. Both `name` and `description` use this rule: the resulting `name` must equal the directory name, and `description` must be nonempty. Quoted names, name comments, duplicate matching keys, and next-line plain scalars are rejected. Quotes, comments, YAML types and folding/chomping are not decoded; `description: ""`, `>2`, and `| # note` are nonempty raw values. Colon spacing is not YAML-validated, so `name:standard` is also accepted. These are known semantic limits: broader host YAML acceptance does not imply validator acceptance, and validator success does not establish YAML semantics or host acceptance.

Unrelated Markdown outside these seeds and their dependency closure is intentionally outside the reference graph; this is not a repository-wide Markdown linter. Logical targets with `.md`, `.py`, `.ps1`, `.sh` or `.tmpl` suffixes and local Markdown destinations are checked. Existing extensionless logical paths also receive existence/containment checks, including published directories; missing extensionless paths, generated state with other suffixes, absolute/home Markdown destinations, remote URLs and the literal `URL` placeholder are outside the asset graph. Production regression tests retain the existing host publication and source-reference routes.

The exact `link-targets/agents/AGENTS.local.md` overlay is optional and private: it is neither required nor imported, even when present or when Git is unavailable. Other local-instruction paths remain ordinary required targets. Its host-local fallback table is not a shared-repository validation source; the tracked global Claude router and shims remain protected.

A root with a `.git` directory or file requires successful Git inventory, including when the Git binary is unavailable; failures stop instead of importing ignored/private assets. A Git-free root uses filesystem enumeration even inside an unrelated parent checkout. External symlink targets fail closed, and non-ignored candidates intentionally affect validation. Retirement scanning covers those files except the sole history block below and the entire validator/test Python files (which contain regression data). Canonical paths and published aliases are forbidden in active sources; unambiguous retired filenames are also checked when no current inventoried asset shares that filename. Extensionless historical terms are audited in delivery's tracked-source search, not banned lexically. These static checks do not establish host activation.

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
- `link-targets/agents/guides/model-gpt-6.md`
- `link-targets/agents/guides/model-astra.md`
- `link-targets/agents/guides/model-sol.md`
- `link-targets/agents/guides/model-luna.md`
- `link-targets/agents/reference-map.json`
- `link-targets/agents/tools/validate-reference-map.py`
- `link-targets/agents/tools/test-reference-map.py`
<!-- retired-paths:end -->

<!-- reference-kind: manual-navigation; target: link-targets/agents/AGENTS.md -->
<!-- reference-kind: manual-navigation; target: link-targets/agents/guides/github-cli-without-clone.md -->
