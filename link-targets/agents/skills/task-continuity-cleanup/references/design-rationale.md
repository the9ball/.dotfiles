# Design rationale

Read this document only when changing candidate selection, staleness, or
deletion semantics. Routine cleanup does not need this history.

## Decision

Treat task-continuity memos as disposable working-state caches rather than
authoritative records. Select stale candidates using only the filesystem
modification time of direct-child `*.md` files. Use a strict UTC cutoff with a
default age of 30 days.

Do not read memo contents, parse frontmatter, interpret registry status, or
repair session registries during cleanup. Require an explicit user request, a
metadata-only preview, and approval of the exact candidate set before
permanent deletion.

## Why filesystem modification time

The memo schema contains `last_maintained_at`, but maintaining that field
depends on model behavior. The session `active` and `closed` values likewise
record whether the explicit close workflow completed, not whether a session is
still alive. Abandoned, crashed, or silently ended sessions can remain
`active` indefinitely.

During the initial 2026-08-04 design review, the same project memo directory
contained divergent host state: the inspected Claude registry had only
`active` entries, while the Codex registry retained a `closed` entry. Using
registry status as liveness would therefore preserve abandoned memos and make
cleanup behavior differ by host.

Filesystem modification time is updated by actual memo writes, including
mechanical compact-time appends, without reading memo content. A copy, restore,
or explicit timestamp change can postpone deletion, but that is a safe false
negative: stale cache remains longer and no current memo is deleted early.

This choice also keeps candidate discovery mechanical and bounded. The model
sees only path, modification time, and size rather than accumulating memo
contents in context.

## Why registries are out of scope

Task-continuity registries are host-local operational state. A shared project
directory may contain memos created by several hosts, while installation and
test fixtures can carry the same ownership marker as live installations.
Discovering and mutating every possible registry would add host coupling and
could modify unrelated fixture state.

A stale registry entry matters only if that exact session is resumed. The main
task-continuity skill treats a missing memo as discarded volatile state and
reconstructs continuity from available conversation and current primary
evidence. Dangling references are therefore an accepted consequence, not a
cleanup failure.

## Alternatives rejected

- `last_maintained_at`: rejected because its accuracy depends on model
  compliance and requires reading frontmatter.
- Registry `active` exclusion: rejected because `active` is not a reliable
  liveness signal and can make abandoned memos effectively immortal.
- Registry annotation or repair: rejected because it expands cleanup into
  host-specific state discovery without improving safe candidate selection.
- Trash or archive retention: rejected because memos are explicitly
  disposable caches and deletion already requires preview and approval.
- Automatic or scheduled cleanup: rejected because an explicit user trigger
  avoids deleting a memo shortly before a long-dormant task resumes.

## Reconsider this decision when

Re-evaluate the design if memo files become authoritative records, hosts expose
a reliable cross-host liveness or expiration signal, missing memo references
cause runtime failure instead of graceful reconstruction, or metadata-only
candidate previews become too large to review safely.
