# Explicit checklist maintenance

Read this guide only when the user explicitly requests maintenance of [checklist.md](checklist.md). Ordinary code review neither loads this guide nor changes the checklist. A finding may motivate a later request; it never authorizes an automatic update.

Keep the checklist limited to repeatable human quality judgments. Naming, applicable documentation/comments, obsolete code, dependency purpose, and rollback granularity are the initial examples, not a closed taxonomy. Exclude general correctness/safety catchalls already handled by Phase 1 and checks whose useful decision is fully provided by tests, formatters, linters, or scanners.

## Decide the change

- **Add** when evidence from actual reviews establishes a recurring, distinct quality question with a clear applicability rule, observable evidence, and an actionable finding. Specify what human judgment adds beyond automation and Phase 1.
- **Merge** when checks repeatedly ask the same question using the same evidence. Preserve an existing ID only if its meaning remains unchanged; otherwise retire the inputs and allocate a new ID for the merged meaning.
- **Delete** when a check is obsolete, entirely automated, duplicates Phase 1 or another check, or has no usable applicability/evidence boundary. Record the reason and any replacement instead of silently removing its history.
- **Clarify** under the same ID only when wording or examples change without changing applicability, the judgment, or pass/finding criteria. Changed meaning requires retirement and a new ID, including splits and materially broadened or narrowed criteria.

## Preserve identity and traceability

Use `CRQ-` followed by at least three digits. Allocate the next unused number above every active and retired ID; never renumber active checks or reuse retired IDs. Move retired IDs to the checklist's `Retired IDs` section with the former title, reason, replacement IDs or `none`, and maintenance commit/reference. Preserve existing retirement records. A pending change may use a unique maintenance reference, resolved to its commit when committed; do not invent a commit ID.

Before changing a check, inspect callers and reporting references for its ID. Keep prior review records attributable to the checklist version they used; do not relabel their findings with replacement IDs. Changes become effective only for a subsequent fixed review snapshot, never retroactively for a running or completed review.

## Validate the maintained checklist

Check that active and retired IDs are unique and disjoint, new IDs exceed the previous maximum, changed meanings receive new IDs, and retirement records explain every removed ID. Verify relative links and Markdown whitespace. Confirm that every active check still supports `APPLICABLE` / `NOT_APPLICABLE` / `UNVERIFIED` applicability, `PASS` / `FINDING` / `UNVERIFIED` / `NOT_APPLICABLE` results, and reasons with path/line and commit/tree evidence. Excluded checks retain `NOT_APPLICABLE` results and are not counted as performed checks.

Report the changed IDs, their rationale, retirements/replacements, and validation limits. Keep changes within the requested maintenance scope; scripts, agent settings, automatic checklist updates, code fixes, and external posting require their own authorization.
