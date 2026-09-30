# History of review-watch policy changes

`SKILL.md` describes the procedures that are valid now. This file keeps only policy changes whose reasons are worth
referring to on their own later. Wording fixes and minor additions are not recorded.

## 2026-08-24 Moved pre-review from the monitoring session to a separate session

HEAD: `0cdae10cb6ef5ad57cef65120d0f15c6abb7307e`

### Summary of the change

Changed who carries out the pre-review.

- Before: The monitoring session received the notification, delegated the pre-review straight to a subagent,
  received the conclusion, and wrote the report. Delegation was mandatory regardless of the size of the diff.
- After: **The monitoring session only notifies, and the pre-review is done in a separate session.**
  The pre-review session may read the PR itself, and chooses whether to delegate to subagents by scale.

The storage location and naming rules for the materials were changed at the same time (described below).

### Reason

Delegation protects only the monitoring session's context, and **the basis of each finding remains with no one.**
Only the conclusion comes back from the subagent, so when someone asks "show the basis for this finding" or "check whether the same pattern
exists elsewhere", someone has to reread the diff.
In actual measurement as well, for a PR of 60 files and +3188/-34, what came back was a one-line summary.

If the pre-review session is separate, the one who read the PR becomes the discussion partner as is. The rereading disappears,
and so does the trouble of writing out a handoff prompt. The lightness of the monitoring session is
protected more strongly than before by "not pre-reviewing at all".

As a by-product, delegation could be changed from mandatory to optional. Delegation to protect the monitoring session is no longer needed,
and whether to read the PR yourself can be chosen according to its scale. Delegating less also reduces the cost of verification
needed to avoid accepting delegates' reports at face value.

### Alternatives considered

**Resume the subagent that did the pre-review with `SendMessage` and ask follow-up questions.**
It is cheap because the state of having read the diff is kept, but the answers come back through the monitoring session,
so the longer the discussion goes on, the heavier the monitoring session becomes.

**This was not adopted and is not used in current operation.** Pre-review in the monitoring session is
prohibited regardless of the number of round trips (`SKILL.md` A-4), and there is no exception here.
It is true that "one or two round trips are cheap", but accepting that would leave no way to draw the line of the prohibition.

**Continue the discussion in the monitoring session.** This takes the least effort, but it is exactly the form we wanted to avoid.
Carrying even one pre-review leaves its weight from then on, and compaction cannot be invoked by the session itself
(`/compact` is a user-side command), so it also cannot choose when automatic summarization runs.

**Have the monitoring session generate a handoff prompt that the user pastes into another session.**
This was actually considered once. If the storage location and naming rules for the materials are made to follow from the PR number,
writing out a prompt becomes unnecessary in the first place, so it was not adopted.

### Impact

- Moving from the monitoring session to a pre-review session becomes a manual step. The user has to open a new session and
  tell it the target PR. The materials can be found from the identifier, so
  the PR URL (or `owner/repo#number`) is all that needs to be conveyed.
  This judgment was first written as "the PR number alone is enough", but numbers are assigned per repository,
  so the number alone does not determine the repository. This was pointed out in a review on the same day and corrected.
- A pre-review session is assumed to be single-use for one PR. If one session carries multiple PRs,
  the problem that occurred in the monitoring session recurs in a different place.

## 2026-08-24 Removed the GUID from the report file name

HEAD: `0cdae10cb6ef5ad57cef65120d0f15c6abb7307e`

### Summary of the change

- Before: `<owner>-<repo>-<PR number>-<first 8 characters of GUID>.html`
- After: `<owner><repo>-<PR number>.html`. The diff is also placed in the same location as
  `<owner><repo>-<PR number>.diff`. A repeated pre-review overwrites them.
  The `/` in `owner/repo` is removed and the parts are concatenated so as not to add a delimiter.

The location of the diff was also changed. It moved from the session-specific scratchpad to `%TEMP%\claude-pr-review\`,
and `*.diff` was added to the targets of the 7-day cleanup.

### Reason

**The combination of owner, repo, and PR number is unique for one PR, so adding a GUID had no point.**
The GUID had been added "so that pre-reviewing the same PR twice would not overwrite the previous report",
but in practice there was no case where being overwritten caused trouble. Rather, because the suffix was random,
when there were several reports for the same PR, new and old could not be told apart.

The effect of removing it shows up in handover. **The path can be computed from the identifier (owner, repo, PR number)**,
so another session does not need to search with globs and can reach the previous materials just by specifying the PR.

The diff was moved out of the scratchpad for the same reason. The scratchpad path contains the session ID
(`.../<session-id>/scratchpad/`) and disappears when the session ends, so another session cannot take it over.

We accept the possibility that a failed overwrite leaves a broken report. Writing to a temporary name and then renaming
would prevent it, but that is excessive for a volatile file, and if it breaks it can simply be recreated.
