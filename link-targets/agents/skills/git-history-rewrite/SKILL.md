---
name: git-history-rewrite
description: >
  Rewrite commit history (reorder, squash, split, drop, fix past commits, rebase onto a new base (ベース付け替え)) non-interactively without using `git rebase -i`.
  Defines history replay with cherry-pick, selection of the shortest method for each purpose,
  verification of rewrite results with `git range-diff`, and reflecting the result onto the original branch.
  Referenced for requests such as 「コミットをまとめたい」 (combine commits), 「順番を入れ替えたい」 (reorder), 「途中のコミットを直したい」 (fix intermediate commits), 「rebase したい」
  and 「履歴を整理したい」 (clean up history), and for conflict handling during a rebase.
---

# Git History Rewrite (non-interactive)

`git rebase -i` is prohibited by the harness rules (it is a command that opens an interactive editor).
**Do not use the workaround of mechanically rewriting the todo through `GIT_SEQUENCE_EDITOR` / `sequence.editor`**
(it goes against the intent of the rule, and a mistake in rewriting the todo silently destroys history).
Instead, use suitable non-interactive commands or history replay with cherry-pick.

## Overview of the procedure

0. Prior confirmation → 1. Select method → 2. Execution → 3. Verification → 4. Reflect to original branch → 5. Clean up

Do not skip verification (3). A rewrite accident cannot be noticed until you look at the difference.

## 0. Prior confirmation

```bash
git status --porcelain
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
git log --oneline --no-decorate <base>..HEAD
```

- Do not start rewriting history unless the working tree is clean. Ask the user to commit or stash.
- Always record the output of `git rev-parse HEAD` (the SHA of the original tip). It is referred to as `<orig>` from here on.
  Do not rely on the reflog alone (recovery is troublesome if it is lost during the procedure).
- `<base>` is the starting point of the rewrite. If you do not know it, suggest candidates using `git merge-base HEAD origin/main` or similar and
  ask the user. Do not guess.
- Check whether the original branch has been pushed (`git rev-parse --abbrev-ref '@{upstream}'`).
  If it has already been pushed, tell the user first that the later reflection will involve a force push.

## 1. Choice of means

Cherry-pick replay is versatile but takes a lot of work. If your purpose fits in one of the first three rows of the table below, use that.

| What I want to do | Means |
|---|---|
| Edit the last message/content | `git commit --amend` (pass the message as `-m`) |
| Combine the latest N items into one | `git reset --soft HEAD~N` + `git commit -m "..."` |
| Just replace the base (order and contents remain the same) | `git rebase --onto <new-base> <old-base> <branch>` |
| Modify/reorder/split/drop commits other than the last one | cherry-pick replay (step 2) |

`git rebase --onto` is non-interactive, so you can use it. Do not include `-i`.

## 2. cherry-pick replay

```bash
# Create a temporary branch from the base (use -c, not -C)
git switch -c rewrite/<original branch name> <base>

# Stack them in the desired order
git cherry-pick <sha-a>
git cherry-pick <sha-b> <sha-c>
```

- **Use `-c` instead of `-C`.** `-C` forcibly recreates a branch of the same name, so the previous attempt
  would silently disappear. If the branch already exists and an error occurs, check its contents and ask the user how to handle it.
- The two-step approach of "`switch -C` then `reset --hard <base>`" is unnecessary. The single command
  `switch -c <temp branch name> <base>` is enough. What is created here is a new branch with a name different from the original branch, so the original branch ref does not move
  and the original tip (`<orig>`) is not lost.

Type per operation:

- **drop**: Do not cherry-pick the SHA.
- **Sort**: Change the order of cherry-pick.
- **squash**: Stack the range to be combined in the index with `git cherry-pick -n <sha>...`, and finally run `git commit -m "..."`.
- **Message change**: `git cherry-pick <sha>` followed by `git commit --amend -m "..."`.
  `-e` / `--edit` opens the editor, so do not use it.
- **Content correction**: Edit the file immediately after cherry-picking the target, `git add` + `git commit --amend --no-edit`.
- **Split**: Apply the commit without committing using `git cherry-pick -n <sha>`, unstage with `git reset HEAD`, then
  repeat `git add` + `git commit` for each chunk you need.

## Conflict handling

```bash
git status            # conflicting files and progress
# After resolving the file
git add <resolved file>
git -c core.editor=true cherry-pick --continue
```

- `cherry-pick --continue` does not open an editor unless the original cherry-pick was started with `-e` / `--edit` (confirmed with Git 2.55; it does not hang even with `core.editor=vim`). The `git -c core.editor=true` prefix above is insurance in case `-e` was attached accidentally. This editor override is different from mechanically rewriting the todo; it is harmless, so keep it, and it exists only to prevent a hang.
- If `git config --get rerere.enabled` is `true`, a recorded conflict resolution is applied automatically
  when the same conflict is met again. If a replay is likely, enabling it in advance makes rework easier
  (ask the user before changing global settings).
- **Do not use `git cherry-pick --skip` on your own judgment.** This operation discards the whole commit, so
  always confirm with the user unless it is an intended drop.
- Do not try to resolve a conflict when you cannot tell how to resolve it. `git cherry-pick --abort` returns the temporary branch to its previous
  state (the original branch is untouched), so report the conflict to the user and ask for instructions.
- You can check the remaining picks at `.git/sequencer/todo`.

## 3. Verification (required)

Perform two checks with different roles. Only the former can be used to decide pass/fail mechanically; the latter is for visual inspection.

### 3-1. Tree matching (pass/fail gate)

If you only want to sort, squash, or change the message, but the final content should remain the same:

```bash
git diff <orig> HEAD   # the output should be empty
```

If it is not empty, either a cherry-pick was missed or a conflict was resolved wrongly. Identify the cause and redo the work instead of moving on to the reflection.

It will not be empty if it includes an intended drop or content change, so confirm that the output consists **only** of the intended changes.

### 3-2. Review by commit

```bash
git range-diff <base>..<orig> <base>..HEAD
```

Check the commit correspondence with the symbols `=` (unchanged) / `!` (changed) / `<` `>` (present on one side only). What to look for is
whether commits that were supposed to be dropped have disappeared, whether unintended message changes have crept in, and whether a split
has the intended granularity.

- **It is not abnormal in itself for `range-diff` to show differences in commit contents.** Reordering commits that touch the same area changes individual patches even when the final trees match exactly. Do not use the presence or absence of differences as a pass/fail judgment; see 3-1 for the actual pass/fail criteria.

Report the verification results to the user together with the lists of commits before and after the rewrite.

## 4. Reflection to the original branch

**This operation must be performed with explicit user approval.** Leave the branch as a temporary branch before approval.

```bash
git branch -f <original branch> HEAD
git switch <original branch>
```

For pushed branches, always use `--force-with-lease` for push. Do not use plain `--force`.

```bash
git push --force-with-lease origin <original branch>
```

Push only when the user explicitly instructs it. Do not push merely because verification passed.

## 5. Clean up

```bash
git branch -d rewrite/<original branch name>
```

- Delete the temporary branch with `-d` (deletes only merged branches). Do not use `-D`.
- Leave the original branch and saved `<orig>` visible until the user confirms the results.

## What not to do

- Use of `git rebase -i` and mechanical rewriting of todo with `GIT_SEQUENCE_EDITOR` / `sequence.editor`.
- Skip verification (step 3) and reflect/push.
- `git branch -f` / `git push --force*` / `git reset --hard` / `cherry-pick --skip` without user approval.
- Start rewriting the history when the work tree is dirty.
