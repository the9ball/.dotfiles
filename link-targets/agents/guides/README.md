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

## Issue #128 migration evidence

Baseline: `edeebb2ce538ba1e768c878cb9ea831741be6d9b`. The inventory was checked with tracked-source searches, structured parsing of the baseline inventory, and inspection of both baseline Python tools. No tracked CI or hook invokes the old validator. The pre-change validator passed (51 nodes, 90 declared edges, 80 acyclic edges, one external consumer); all 23 baseline regression tests passed. Those counts describe the baseline, not acceptance criteria for the derived graph.

### Consumer inventory

Paths in the first four rows are relative to the canonical agents directory. The retired filenames in this section describe history, not loading instructions.

| Class | Baseline consumers | Migration |
| --- | --- | --- |
| Runtime root resolution | `skills/{advisor-review,delegation,git-operations,implementation-planning,review-consolidation}/SKILL.md` | Use the single Reference path procedure above; instruction and work roots remain independent. |
| Indirect runtime policy | `skills/execution-lifecycle-gate/SKILL.md`, `skills/github/SKILL.md` | Remove ancestor-map/routing-guarantee claims; canonical Skills and host instructions govern routing. |
| Static validation | `tools/validate-reference-map.py`, `tools/test-reference-map.py` | Replace with source-derived checks and invariant regression tests; no handwritten node/edge inventory. |
| Documentation and preservation | `guides/README.md`, `guides/github-cli-without-clone.md` | Source-local placement, retirement history, external-consumer note and fallback declarations. |
| Host read boundary | `chezmoi/dot_codex-personal/AGENTS.local.md` | Read canonical placement text only when necessary; keep executable tools outside the exception. |
| Layout documentation | `link-targets/README.md` | Remove the obsolete inventory entry. |
| Preserved host paths | Global Claude table, shared host-local table, publication scripts, architect and WSL routes | Twelve shims and dispatch tables unchanged; WSL navigation annotations retain the existing non-dependency meaning. |

The map was a static inventory and a dependency of agent-facing resolver instructions. No tracked host implementation used its discovery strings as a loader. Inventory-only Skill-directory edges were replaced by discovery/source enumeration; other declared-only policy routes were already named by canonical instructions. Dormant assets outside the managed migration closure are not claimed to have received a general repository documentation audit.

### Invariant migration matrix

| Protected property | Decision and canonical authority | Executable evidence |
| --- | --- | --- |
| Root identity and failure behavior | Replace JSON root field with resolved loaded entity plus unique canonical sentinels. | `instruction_root`; valid/Git-free, missing/nonfile/malformed/ambiguous roots, symlink/junction, broken target and escaping sentinel tests. |
| Missing targets and containment | Retain in actual logical instruction references and file-relative Markdown links. | `resolve_target`, `references`; missing logical/Markdown targets and traversal/escape tests. |
| Orphan references | Retain actual guide caller requirement; an external-only note is distinct from activation. | Derived caller graph and orphan/external-consumer fixtures. |
| Cycles | Retain actual read-dependency cycle detection. Source-local exceptions preserve only navigation/policy precedence. | Cycle, invalid/unbacked/duplicate annotation, explicit and relative/multiline loader fixtures. |
| Normative owner uniqueness | Replace separate owner records with same-name shim ownership and canonical Skill Guide. | Exact thin-template, duplicate/missing owner, owner drift and hidden legacy-loader tests. |
| Required/exempt discovery coverage | Retain the classification at the owning Skill; derive coverage independently from host/shim/direct routes. | Frontmatter, discovery/failure, missing whole contracts, required coverage, exempt-with-shim and missing direct-route tests. |
| Router → shim → owner | Retain actual global host references and source-only thin shim. | Missing router, missing shim heading, matching owner and preserved production route checks. |
| Shim runtime rules and retirement | Retain exact rule-free shim plus Issue #75 gate in shim and host instructions. | Extra runtime rule, changed retirement, lost host gate and production coverage tests. |
| Retired paths | Retain this bounded history as authority; disallow reintroduction and active source use. | Existing-retired-file, active-reference, malformed-history fixtures; tracked/candidate source scan. |
| External consumer | Retain GPT-Chat and purpose in the external guide itself. | External-only note check; it never supplies a runtime caller. |
| Conditional/model closure | Retain actual authorization/Advisor/planning dependencies and model-table compositions. | Production graph assertions and GPT-6 family/variant plus GPT-5.6 mappings. |
| JSON schema, node counts, duplicate registrations and source↔map drift | Remove: there is no second representation to synchronize. Derive inventory/edges from source and deduplicate repeated references. | Production validator plus above behavioral tests replace registry-shape tests. |
| Classification strings | Remove redundant inventory strings; retain the placement-policy boundary against using descriptive metadata as authorization. | Policy inspection; no activation/model/permission decision reads inventory metadata. |

### Host evidence and limits

- Windows Python 3.13: validator and 28 regression tests pass, with three symlink-privilege cases skipped. The real junction fixture runs, including failure after its loaded target disappears. Published `.agents` and `.claude/skills` paths were separately resolved to the canonical instruction tree. Logical paths reject drive-qualified forms, including an existing in-root absolute target.
- WSL Ubuntu Python 3.8: validator and the same suite pass; only the Windows-specific junction test is skipped. POSIX symlink success, broken-target and escape cases execute here. Outside-CWD execution is tested on both platforms.
- Claude Code: reuse [Issue #75](https://github.com/the9ball/.dotfiles/issues/75) observations from version 2.1.270: explicit `/structured-data` works; the corresponding natural-language request does not auto-activate and stops fail-safe; negative control does not load; unresolved conditional inputs stop. These are route-specific historical observations, not fresh candidate runtime tests. Dispatch and supported-trigger policy are unchanged; no shim retirement is inferred. Python path probes establish filesystem mechanics, not Claude interpretation of the new prose.
- Codex: this implementation session resolves the published Windows instruction paths and applies the new canonical procedure; static checks do not claim a fresh exhaustive discovery experiment.
- ChatGPT Web: the GPT-Chat external guide remains; no local-filesystem execution is asserted. Native macOS and Linux hosts were not run separately from WSL.
- Updated Skills pass the Skill authoring validator in UTF-8 mode; changed files pass EditorConfig checker, Python syntax/documentation checks and Git whitespace checks. No applicable EditorConfig properties were present; UTF-8, LF and existing indentation were preserved. Commit hooks run the configured secret scan.

The replacement introduces two Python files, no runtime loader, new classes, packages or central registry. It stays below the estimated production size because map schema and duplicated metadata disappear; no required error branch or invariant was omitted. Roll back the complete implementation commit as one unit to restore the map, resolver clauses and tools together; do not restore only one old component. The separate evidence-documentation commit can be rolled back independently.
