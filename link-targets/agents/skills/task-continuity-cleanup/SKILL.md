---
name: task-continuity-cleanup
description: List and permanently delete stale Markdown memo files directly under explicitly selected `.task-continuity` directories using filesystem modification times only. Use only when the user explicitly asks to inspect, clean up, prune, or delete old task-continuity memo files. Never invoke for ordinary task-continuity maintenance, merely because memos are old, or on a schedule.
---

# Task Continuity Cleanup

Treat task-continuity memos as disposable working-state caches. Remove stale
memos only through an explicit, previewed cleanup operation.

When changing candidate selection or deletion semantics, read
`references/design-rationale.md` first. Do not load it during routine cleanup.

## Resolve the cleanup scope

Accept zero or more user-selected paths and a staleness threshold in days.
Use 30 days by default. When no path is selected, use the current Git root, or
the current working directory when no Git root exists. Require the threshold
to be a finite, non-negative number; reject an invalid or negative value.

For each selected path:

1. Resolve it to an absolute path.
2. If its final component is `.task-continuity`, use it directly. Otherwise
   append `.task-continuity` and resolve again.
3. Require the resulting directory's final component to equal
   `.task-continuity` exactly.
4. Require the resulting directory to exist. Report a missing directory as a
   selected-path error, never as an empty or already-clean result.
5. Reject a symbolic link, reparse point, junction, or non-directory target.

Never search recursively for other `.task-continuity` directories. Multiple
explicitly selected directories are allowed.

## Build a metadata-only preview

Determine the cutoff in UTC. A file is stale only when its filesystem
modification time is strictly earlier than `now - threshold`; do not round to
calendar dates.

Inspect only direct children matching `*.md`. Do not recurse, follow links, or
read file contents or frontmatter. Require each candidate to be a regular file
and not a symbolic link or reparse point. Collect only its absolute path,
modification time, and size. Preserve the full-precision machine timestamp
captured during preview, such as filesystem ticks or nanoseconds, for later
comparison. Never reconstruct that value from human-readable display text.

`TASK_CONTINUITY_ACTIVE_MEMO_PATH`, when present in hook context, is
model-visible context rather than a process environment variable. Normalize
that absolute path and exclude the exact file from the preview. If a helper
command performs enumeration, pass the exclusion path to it explicitly. Do
not infer a replacement exclusion when the label is absent.

Do not read or write any task-continuity session registry. Registry status,
stale references, ownership records, and fixture installations are outside
this skill's scope.

Show the selected directories, threshold, cutoff, candidate count, and a list
containing path, size, UTC modification time, and local modification time with
an explicit UTC offset. Display formatting must not replace the preserved
machine timestamp. If there are no candidates, report that no cleanup is
needed and stop.

## Obtain deletion approval

Ask the user to approve the exact previewed candidate set before deleting
anything. A `.allow-write` marker authorizes task-continuity runtime writes;
it never authorizes cleanup or deletion.

Approval applies only to the displayed candidates. Re-preview after the user
changes the directories, threshold, or candidate set.

## Delete approved candidates

Immediately before deleting each approved path, inspect its metadata again.
Delete it only when all of the following remain true:

- It is the same direct child of the approved `.task-continuity` directory.
- It still matches `*.md`.
- It is still a regular non-symbolic, non-reparse-point file.
- Its full-precision machine modification time and size exactly match the
  values captured for the approved preview.
- Its modification time is still strictly older than the cutoff.
- It is not the normalized current-session memo exclusion.

Classify a candidate whose metadata changed as `skipped_changed`; do not read
it to decide whether deletion is safe. Permanently delete eligible files
without moving them to trash or an archive.

Never delete `.allow-write`, `.gitignore`, directories, non-Markdown files,
or files outside the exact approved directories. Do not modify registries even
when they continue to reference deleted memos.

Report deleted, skipped, and failed paths separately. Include the error for
each failure and do not claim full success after a partial failure.
