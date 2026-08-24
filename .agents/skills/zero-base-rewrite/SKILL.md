---
name: zero-base-rewrite
description: Rewrite a document-like text artifact as a self-contained final version when its meaning depends on conversation or earlier drafts and the user asks for 「清書して」 or a full zero-based rewrite. Preserve verified content and uncertainty, snapshot and compare the source, and stop when evidence or format safety is insufficient. Exclude source code, raw data, and history-bearing or legally authoritative documents.
---

# Zero-Base Rewrite

## Purpose

Reconstruct a document-like text artifact so a reader who has not seen the conversation, earlier drafts, or editing history can understand it on its own.

“Zero-base” permits rebuilding the structure, order, and wording. It does not permit discarding facts, requirements, constraints, rationale, document status, or uncertainty. Do not invent historical claims, approvals, or external validation.

## Activation and boundaries

Activate for an explicit request to rewrite from zero or fully reconstruct a document. Activate for the bare phrase 「清書して」 only when the artifact depends on conversation, an earlier draft, relative time, or implicit references and cannot become self-contained through local editing alone. Document length is not a trigger condition.

Do not activate for ordinary proofreading, light copyediting, summarization, translation, shortening, or formatting-only changes when the text is already self-contained. The scope covers Markdown, plain text, plans, specifications, designs, reports, proposals, explanatory materials, report-oriented HTML, and similar document text.

Do not replace source code, configuration, raw data, or documents whose chronology, accountability, change history, audit trail, review response, or authoritative wording is itself required. This includes ADRs, minutes, changelogs, history files, postmortems, audit/legal/contract/regulatory records, authoritative policies, and instruction files. When a target is out of scope, do not rewrite it; offer structure-preserving copyediting, a separate current-state summary, or application limited to non-historical sections.

Signals include paths under `decisions/`, `adr/`, or `history/`, filenames such as `*.history.md`, ADR-numbered stems, and headings covering timelines, rejected alternatives, or superseded decisions.

## Preserve the source

Before changing a file, choose a collision-safe working directory and record three separate paths: an immutable source snapshot, a rewritten output, and a comparison ledger. Use a dedicated repository working directory such as `.zero-base-rewrite/<run-id>/`, or a temporary directory when the source is outside a repository. Do not place either output where an unrelated commit could pick it up without the user knowing.

Do not skip or discard the snapshot because the source or backup is covered by `.gitignore`, untracked, or outside the next commit. Git status is a cleanup concern, not a preservation condition. Keep the snapshot and ledger through comparison and acceptance; do not silently delete them. Never overwrite the source file. If the input exists only in the conversation, retain its exact text as the comparison source and do not invent a filesystem path.

## Workflow

1. Identify the intended reader, purpose, output format, and references available to that reader. Detect whether chronology or authoritative wording is part of the document's purpose.
2. For an in-scope file, create the source snapshot, separate output path, and ledger path before any mutation. Stop if safe separate paths cannot be secured.
3. Record every relevant source item in the ledger: facts, requirements, constraints, interfaces, invariants, exceptions, scope, rationale, document status and approval state, assumptions, unresolved items, and required references.
4. Independently extract high-risk tokens from the source: numbers, dates, proper nouns, paths, identifiers, URLs, and defined terms. Record the heading/topic inventory by meaning rather than requiring identical headings.
5. Rebuild the artifact from a suitable structure. Remove conversation-dependent wording, but preserve the meaning and certainty of confirmed, assumed, proposed, and unresolved statements. Keep reader-relevant uncertainty in the document itself.
6. For HTML, check IDs, classes, CSS selectors, and JavaScript DOM references as linked contracts. Keep each identifier attached to the same content. If references cannot be traced, do not delete, rename, or move existing containers; limit changes to prose inside them. Stop for confirmation if the requested result requires structural changes that cannot be safely traced.
7. Compare the source and result independently: map every ledger item, compare high-risk tokens, check semantic coverage of topics and defined terms, and inspect structural differences. Use word-level diff only as an aid; do not treat line diff as proof of preservation. Check certainty increases and decreases, unsupported additions, omissions, and HTML reference resolution. Revise and compare again when a material discrepancy remains.
8. Return the rewritten artifact, the source/output/ledger paths when applicable, a concise comparison status, and unresolved items or blockers. Do not present an editing diary unless requested.

## Required invariants

- Do not add facts, decisions, causes, approvals, requirements, or references absent from the source or the user's explicit input.
- Do not change the meaning or certainty of confirmed requirements, constraints, interfaces, invariants, exceptions, guarantees, or status labels.
- Do not turn an unresolved contradiction or TODO into a decision. If the reader needs the uncertainty, state it in a self-contained section; report only delivery blockers separately.
- Replace phrases such as 「今回」「先ほど」「前案」「修正後」「議論のとおり」 with wording that stands alone, or remove them when the source provides no supported replacement.
- Preserve necessary rationale as durable constraints and facts, not as inaccessible conversation history.
- Do not claim review, approval, validation, or external verification unless explicitly established by the source or user.

## Stop and ask

Stop instead of guessing when the document's history is evidence, safe source/output/ledger paths cannot be secured, HTML references cannot be traced for a required structural change, comparison leaves a material omission or unsupported addition, certainty changes cannot be resolved, or the source contradiction must be arbitrarily decided to make the artifact coherent.

## Quality gate

Before delivery, confirm that a new reader can identify purpose, scope, actors, conditions, behavior, exceptions, and status without the conversation; every ledger item and high-risk token is accounted for; no unsupported claim or certainty change was introduced; unresolved items remain visible; required format structure is usable; and the source snapshot, output, ledger, and comparison status are reported.
