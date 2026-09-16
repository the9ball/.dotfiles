---
name: git-stage-lines
description: Safely stage only selected working-tree Git changes by line range or diff hunk, without changing the working tree or discarding existing staged changes. Use for requests such as “この変更だけstageして”, “42〜57行目だけgit addして”, “変更1と3だけstageして”, “commit A用の変更だけstageして”, or “git add -p相当を非対話的にやって”.
---

# Git Stage Lines

Use `bin/git-stage-lines.mjs` with Node.js 20 or newer. It creates and checks a
patch, then applies it only to the index.

## Procedure

1. Inspect `git status --short`, `git diff -- <path>`, and
   `git diff --cached -- <path>`.
2. For change numbers, run `--list -- <path>`, retain the fingerprint printed
   to stderr, and pass it with `--fingerprint`.
3. Run `--dry-run` before applying when the list shows an unexpected deletion
   count, a replacement hunk, or another non-obvious selection.
4. Apply the selection, then verify `git diff --cached -- <path>` and the
   remaining unstaged diff. A mismatch is failure.

Examples:

    node "$HOME/.agents/skills/git-stage-lines/bin/git-stage-lines.mjs" --list -- src/foo.ts
    node "$HOME/.agents/skills/git-stage-lines/bin/git-stage-lines.mjs" -- src/foo.ts 42-57
    node "$HOME/.agents/skills/git-stage-lines/bin/git-stage-lines.mjs" --dry-run -- src/foo.ts 42-57
    node "$HOME/.agents/skills/git-stage-lines/bin/git-stage-lines.mjs" --changes 1,3 --fingerprint HASH -- src/foo.ts

Use the `--changes` example for deletion-only hunks; it is their only selection path.

## Rules

- Put the path after `--`; do not pass an ambiguous request or infer nearby changes.
- `--changes` requires the exact fingerprint from the preceding `--list`.
- Normalize overlapping or adjacent line ranges by merging them; do not add lines outside their union.
- Select complete text hunks only. `L` uses new-side lines and `D` uses old-side
  lines; deletion hunks require `--changes`. Replacement hunks show both sides,
  for example `L20/D20-80 (+1/-61)`, and are staged as one unit.
- Preserve existing staged changes and never rewrite the working tree.
- Reject unsupported renames, copies, binary files, symlinks, submodules,
  mode-only changes, conflicts, malformed hunks, and failed verification.
- Exit codes: `0` success, `1` internal error, `2` fix the request, `3` unsupported target/runtime, `4` safety check failure or changed state, `5` Git failure.

Implementation: `bin/git-stage-lines.mjs`. Tests: `tests/git-stage-lines.test.mjs`.
