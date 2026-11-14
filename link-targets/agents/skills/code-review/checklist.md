# Phase 2 quality checklist

Read this reference only for Phase 2, after Phase 1 has completed under the current review contract. These are repeatable human quality checks, not an exhaustive correctness review or a replacement for automated validation. Examples illustrate the checks; they do not limit them.

Record one row for every active ID at the fixed reviewed commit/tree. Use these fields:

| ID | Applicability | Result | Reason | Evidence |
| --- | --- | --- | --- | --- |

- Applicability: `APPLICABLE`, `NOT_APPLICABLE`, or `UNVERIFIED`. Missing evidence is `UNVERIFIED`, never `NOT_APPLICABLE`.
- Result: `PASS`, `FINDING`, `UNVERIFIED`, or `NOT_APPLICABLE`. `APPLICABLE` permits `PASS`, `FINDING`, or `UNVERIFIED`; `NOT_APPLICABLE` applicability requires `NOT_APPLICABLE` result and an evidenced exclusion; `UNVERIFIED` applicability requires `UNVERIFIED` result. Excluded checks are not counted as performed checks.
- Give a reason for every row, including exclusions and passes. Cite reviewed paths and line numbers plus the commit/tree identity; for commit structure, also cite the relevant commit IDs. For an absence claim, state the bounded files or references inspected. For unavailable evidence, identify the missing source and its effect.
- A substantive correctness, compatibility, or safety defect discovered here returns to Phase 1 through the root. A checklist pass cannot override that defect or unresolved evidence. Do not edit this checklist during a review.

## Active checks

### CRQ-001: Names communicate intent

For changed identifiers, check that names describe their domain role, operation, units, or state without requiring the implementation to decode them. For example, a timeout expressed in milliseconds should not use an ambiguous duration name. Inspect representative declarations and callers; do not substitute spelling or naming-style lint results for this judgment.

### CRQ-002: Names follow surrounding conventions

Compare changed names with nearby code serving the same role. Check that equivalent concepts use established vocabulary and that a deliberate departure has a concrete reason. For example, a new repository method should not introduce a second term for the same entity without distinguishing its meaning. Mark this check not applicable only when there is no relevant surrounding convention, and cite the inspected scope.

### CRQ-003: Required documentation and comments exist

Resolve applicable repository comment/documentation rules and inspect changed declarations or complex logic to which those rules apply. Check that required documentation identifies the role and relevant contracts rather than merely repeating the name. For example, a required method comment should explain a non-obvious ownership or precondition. Do not invent universal documentation requirements when the repository has none.

### CRQ-004: Documentation and comments remain accurate

Compare affected comments and documentation with the changed implementation and its callers. Check that described responsibilities, inputs, outputs, side effects, constraints, and failure behavior remain accurate wherever they are documented. For example, a comment promising a read-only operation must not survive newly introduced writes. Cite both the description and the implementation supporting the conclusion.

### CRQ-005: Obsolete and dead code is addressed

Inspect replaced paths and affected references for superseded helpers, unreachable branches, abandoned feature paths, or comments describing removed behavior. Establish actual callers or retention reasons before calling code dead; extension hooks and externally invoked APIs require evidence beyond a local text search. For example, replacing a parser should not leave its unused adapter and obsolete instructions without a reason.

### CRQ-006: Added dependencies have a concrete purpose

For new or newly used libraries, services, or internal modules, connect the dependency to the changed requirement and compare with existing project facilities. Check that its role justifies the added coupling and maintenance cost. For example, adding a package for one trivial transformation needs a reason when an established project utility already handles it. This check does not repeat vulnerability scanning or package-format linting.

### CRQ-007: Commits support understandable rollback

Inspect the reviewed commit sequence for coherent purposes and dependencies. Check whether a change that may need independent rollback is mixed with unrelated behavior or cleanup, and whether required companion changes remain together or have an explicit order. For example, mixing a feature with an unrelated rename makes targeted rollback harder. Assess the actual commit range; a working-tree-only target without a proposed commit sequence leaves this check unverified. Do not rewrite history as part of review.

## Retired IDs

None. ID allocation and retirement are managed only through explicitly requested checklist maintenance.
