# Task-specific guides and shared contracts

A directory for detailed guidelines to read after skill discovery and shared contracts resolved conditionally by a Skill. The normative runtime contract of the migrated workflow is owned by the `## Guide` section of the corresponding `SKILL.md`, and the Skill must not be structured to load this directory.

Since `~/.dotfiles/link-targets/agents/AGENTS.md` is constantly read during all tasks, the more items are added, the lower the compliance rate for individual instructions becomes. Therefore, details that are not always needed are split out into the discovery metadata and the runtime Guide section of the corresponding skill, leaving only the policy kernel on the AGENTS.md side.

The runtime contract of the migrated workflow has the Guide section of the corresponding skill as its only original. Until Claude Code's natural-language skill discovery is verified in Issue #75, the old guide path registered in compatibility_fallbacks of reference-map will be maintained as a host shim without runtime rules, so that the owner skill can be reached from the global Claude host layer.

Issue #75 closes all shims and host fallbacks listed in the registry, regardless of whether they are in the first or second group. Natural-language skill discovery is not a merge prerequisite for this transition; this migration keeps explicit Claude delegations from Codex reachable to the owner Skill.

## Placement rules

- The file name should be ASCII kebab-case.
- For each file maintained as a shared reference, register the classification, reference source, reference purpose, and resolution path in `link-targets/agents/reference-map.json`. A file for which `inbound_required` is true must be referenced by at least one caller in the repository. Consumers outside the repository are registered separately in `external_consumers` and are not used as a substitute for the activation path within the repository.
- Files read from the repository runtime must have an invocation path from either AGENTS.md, Skill, or host integration. A shared reference that is used only from outside the repository is registered in `external_consumers` and separated from the repository activation requirement as `inbound_required: false`. The runtime contract of the Skill is completed within the Skill itself, and there is no structure left to load the old guide from the Skill. The host fallback shim during the transition period will be specified as a compatibility edge pointing to the skill in the opposite direction.
- [`github-cli-without-clone.md`](github-cli-without-clone.md) is maintained as an external shared reference referenced from GPT-Chat. Its use by GPT-Chat is registered in `external_consumers` of `reference-map.json`; do not confuse it with a runtime caller in the repository.
- `*.design.md` is not a copy or change history of the corresponding normative/runtime contract, but a non-normative design companion that includes future options, reconsideration materials/conditions, responsibility boundaries, etc. Normally, it is not loaded at runtime and is referenced only when changing, redesigning, or reviewing the contract of a skill that has companions.
- Do not write content that contradicts AGENTS.md. In case of conflict, AGENTS.md takes precedence.
- On the AGENTS.md side, leave a core that can at least function without reading the files in this directory. Do not create a configuration where the effect is zero if no reading is performed.

## Reference path

- `instruction root` points to the root of the repository that contains the canonical source of the shared instruction tree and `link-targets/agents/reference-map.json`. In this repository, `.dotfiles` is its root.
- `work root` refers to the root of the target repository to be changed/reviewed in the current request. The Git target, difference, target identity, and dirty state are not derived from the instruction root, but are fixed separately from the request and current Git state.
- When referencing another file from the body of a shared reference, use a logical relative path based on the instruction root (for example, `link-targets/agents/guides/<name>.md`).
- Do not write `../../` based on the Skill location or host-specific absolute paths in the body of the shared reference. host integration resolves the instruction root at runtime and then uses logical relative paths.
- When host integration, AGENTS.md, or Skill resolves the instruction root, it resolves the symlink/junction of the loaded file or Skill to the entity path, then traces the ancestors of that entity path to find `link-targets/agents/reference-map.json`, and resolves the JSON's `repository_root` relative to the directory that contains the map. Stop if map is not found, JSON cannot be read as a structure, or no destination exists. Do not implicitly rely on the current working directory or host-specific absolute path.
- When using an instruction-root relative path as a Markdown link destination, use a file relative destination that can actually be resolved from the link source. If you just want to display the logical path, use code span to avoid creating unresolvable root-relative destinations from nested files. Skill uses its own `## Guide` as the normative source and does not refer to the guide path as the runtime loader.
- Invoke `link-targets/agents/tools/validate-reference-map.py` with explicit Python 3 execution to detect missing reference targets, files with zero callers, circular references, skill-discovery metadata problems, compatibility fallbacks without a single owner, and invalid remnants of retired paths. Do not migrate reference routes with validation failures.
- The edges of the reference map are checked for cycles and treated as read dependencies by default. `acyclic: false` is specified together with `acyclic_reason` only for non-dependency edges that are allowlisted by the validator. The currently allowed combinations are `reference-index` / `manual-navigation`, `host-reference` / `manual-navigation`, and `policy-reference` / `policy-precedence`, which records the priority relationship to the always applied kernel. Do not exclude read dependencies such as `workflow-reference`, `contract-reference`, `policy-routing`, `conditional-reference`, and organize the dependencies if there is a cycle.

## Uses of classification

- `classification` in the reference map is inventory metadata that indicates the scope of inventory and review of existing assets, and is not treated as authorization information for skill activation, model suppression, authority, approval, and safety gates.
- When suppressing model-scaffolding or adding lazy loading, do not make a decision based on classification alone, but prepare separate explicit model/capability profiles, separation of mixed clauses, and comparative experiments of representative tasks. Make repository, safety, approval, secret, Git, and user change protection independent from model conditions.
