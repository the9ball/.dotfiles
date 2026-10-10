---
name: review-consolidation
description: For explicit or semantically requested GitHub Issue/PR review maintenance, compresses review information scattered in Issues/Pull Requests into discussion-point (論点) units, and aligns the current work plan and review state with REVIEW-SUMMARY and body.
---

# Review consolidation

## Discovery contract

- Host fallback: exempt; global Claude host instructions route maintenance directly to this Skill

- Positive trigger: For an identifiable GitHub Issue/PR, the user requests 「保守」, 「レビュー保守」, or `review-consolidation`, or clearly requests consolidation of review discussion points or updating the current plan/review state from review conclusions. Judge semantic requests by the intended outcome, not keywords alone.
- Negative trigger: Mere reading/status checks, individual review replies, HANDOFF, unrelated edits or code fixes, quoted trigger words, and discussion or review of this Skill itself. Do not interpret 「保守」 outside GitHub Issue/PR context as a trigger. If the intended outcome cannot be resolved from context, ask only then.
- Conditional dependency: The corresponding Skills for GitHub service, authorization, approval request, and external posting are resolved only when their responsibilities arise.
- Failure mode: If a conditional dependency or target history cannot be resolved, stop in a fail-safe manner without guessing or silent fallback to another route.

## Runtime contract

When this skill is discovered for an applicable request, the contract and orchestration below will be applied as a normative contract. Load conditional dependencies only when necessary, and fail-safely stop them without guesswork or silent omission if they cannot be resolved.

## Guide

Discovery may occur through host-specific instructions or Skill metadata; neither guarantees automatic activation across hosts. Select this Skill only for the positive trigger above, not for every Issue/PR read. If the canonical Skill cannot be loaded, stop rather than assuming its contract.
Responsibilities are limited to semantically compressing scattered review information and aligning the current work plan and review state.
Discovery or invocation does not authorize external changes. Apply existing operation-specific authorization to REVIEW-SUMMARY posting, body updates and Hide separately; a request to organize information only in the conversation is not permission to publish it. Do not disclose private or local information by virtue of Skill selection.

### Trigger and scope

- If the target issue/PR can be uniquely determined from the conversation, it may be estimated, but the target should be visualized at the beginning. Check if it is not unique.
- The work-plan source is the artifact that owns the current work scope. At the issue stage, the Issue body owns the Issue-wide plan; during implementation, each PR carries the current plan for its own scope.
- Treat multiple PRs from one issue as a normal case. 1 PR from multiple issues will not be automatically determined using the standard workflow, but will follow explicit instructions.
- In principle, the impact on the overall plan determined by PR will be fed back into the original Issue through post-merge maintenance (保守) of that Issue, and pre-merge synchronization will only be performed if there is an explicit instruction.
- merge, issue close, HANDOFF, individual review reply, inline comment hide, review thread Resolve, approval/authorization are not the independent responsibilities of this skill.
- For GitHub service/API operations, authorization, approval request, external posting, retry / ambiguous outcome, apply the existing common contract as necessary and do not redefine it with this skill.

### Contract

#### Work plan and body

- Does not require a fixed section schema in the body. Aim for a state in which the current work plan is self-contained and understandable, and if necessary, reorganize the entire work plan to eliminate duplicates and obsolete descriptions.
- Leave only the reasons necessary for execution and design in the body, and send the discussion history to REVIEW-SUMMARY. Undefined matters are also clearly indicated in the body as the current work state.
- At the start of maintenance, check the semantic consistency of body and latest checkpoint. If there is no new review judgment and only the body is old, only body repair will be performed and a new Summary will not be created.
#### REVIEW-SUMMARY checkpoint

Let REVIEW-SUMMARY be a permanent checkpoint for review maintenance. A valid Summary requires the following:

`<!-- REVIEW-SUMMARY -->`

- `今回確定したこと` (What was confirmed this time)
- `未確定として残ること` (What remains unresolved)

Both Japanese headings are required, and if there is no applicable item, write `なし`.

- The summary is organized by discussion point (論点), not by original comment. Identical points must be combined, and independent points within one comment may be separated.
- There is no fixed taxonomy such as acceptance/rejection, and the conclusion and the minimum reasons necessary for later understanding are left in natural sentences.
- The original comment ID/URL, number of characters, and number of items are not specified.
- Do not edit or hide past valid summaries. Unconfirmed matters will be carried over to the subsequent Summary, and even if they are resolved by user responses, a new Summary will be created as a new review state update.
- Although `review round` etc. can be used as an alias during processing, it does not create an independent persistent state.
- Normal review-consolidation does not reply to individual review comments, but instead aggregates the judgments and responses to each discussion point (論点) into a REVIEW-SUMMARY.

#### Checkpoint and history recovery

- Before deciding on checkpoint candidates, complete the acquisition of all necessary top-level comments and check the completeness of the acquisition. If completeness cannot be confirmed, the checkpoint is not finalized and the process is stopped and reported. The checkpoint is the "latest valid REVIEW-SUMMARY" in the acquisition set, and it is semantically determined whether it is reliable for restoring the state, rather than being judged mechanically based only on the marker/heading. An invalid/minimized candidate is not adopted as a checkpoint, but is recovered by tracing back to a reliable point.
- In normal processing with a checkpoint, reviews after that point are treated as differences. However, visible top-level comments are checked to detect past omissions and cleanup candidates.
- If there is no checkpoint, check the review-related history, including hidden / minimized top-level comments and PR inline review comments / threads, and reconstruct the current state. Hide status does not become processed proof.
- If there is not enough pre-reading in a new conversation/thread, a full history audit is used as a basis, but if the necessary history has already been read, a differential can be used.
- If the state cannot be reliably constructed, go back as far as necessary to a point where it is reliable, and if necessary go back to full history. Conflicts that cannot be resolved from the history are returned to undetermined without being inferred.
- The broken Summary is treated as if it did not exist as a checkpoint and is reprocessed from the previous valid checkpoint. If the rescan merely reconfirms the existing valid judgment, it will not be republished in the new Summary.
- Any omissions or contradictions from the past will not be rewritten in the past summary, but will be treated as new targets for judgment in the present.
- An invalid summary can be hidden only if its unique reasons for judgment, counterarguments, verification results, and unresolved information have been transferred to a new valid summary / body without being lost, the replacement destination can be explained, and the target has not changed when reacquired immediately before hiding. If it does not meet the requirements, it will remain visible, and if it is hidden, the user will be notified.
#### Snapshot and review inputs

- The target review set is fixed as a snapshot at the start of one process, and reviews added during processing are not added to the current snapshot. Snapshots and comment ID sets are not persisted.
- Check the new reviews after the snapshot once before completing. If there is a new review, it will not be added to the current target, the user will be notified that unprocessed information remains and the process will end, and the next process will not start automatically.
- Whether a review is input is determined based on the content, not the author, and does not distinguish between human / AI / bot / user-posted AI.
- PR inline review comments / threads are read as input, but inline comment Hide / review thread Resolve is outside the skill range.
- If it is ambiguous whether a comment is a review, confirm as needed. If it is ambiguous whether hiding it is safe, leave it visible.
- Non-review comments and artifacts are not subject to cleanup. Even if the information is referred to as a reference for judgment, it will not be hidden unless it is review input.

#### Cleanup boundary

- Cleanup within Skill is limited to Hide top-level comments treated as reviews.
- Only original comments that have meaningful information stored in body / REVIEW-SUMMARY and are no longer worth displaying are candidates for Hide. Even if undefined matters are included, it is sufficient if the state is preserved.
- Recapture each Hide candidate immediately before execution and confirm that there has been no meaningful change in the text, updated state, or minimized state since the snapshot. If there is a change or cannot be obtained, do not hide the candidate, and do not continue cleanup based on a stale judgment.
- If it is not possible to read-back the establishment of REVIEW-SUMMARY and the body update required this time, it will not proceed to the subsequent Hide. This is a cleanup precondition specific to review-consolidation and is not a redefinition of common authorization/retry.
- Hide reason/category is not fixed. Valid REVIEW-SUMMARY is excluded from Hide, and only invalid Summary is an exception candidate for the above history preservation condition.

#### Ordering and failure

The basic order is as follows.

1. Obtain history, checkpoint, and body and perform necessary consistency checks.
2. Fix the snapshot.
3. Aggregate reviews by discussion point (論点) and make decisions.
4. Post a REVIEW-SUMMARY.
5. Update body to the current state if necessary.
6. Hide top-level comments as necessary.
7. Check new reviews after snapshot and submit final report.
- Does not rollback even if body update or cleanup fails after Summary is established. Even if the Summary succeeds and the body update fails, the checkpoint remains valid so the body can self-heal in subsequent maintenance.
- body is updated only when there is a state change. Re-obtain the body just before writing, and if there is a meaningful change from the snapshot, stop and report without writing.
- Be sure to notify the user of any failures, partial failures, or failures to complete the intended process.

### Orchestration and context management

1. Strictly resolve the loaded Skill entrypoint through every symlink/junction to its existing final file; enumerate its real ancestors whose last two components are `link-targets/agents` and which contain both `AGENTS.md` and `guides/README.md`; require exactly one candidate, with the entrypoint and both sentinels still contained after real-path resolution, and use that candidate's grandparent as the instruction root. Stop on a missing, broken, escaping, malformed, or ambiguous location; never substitute CWD, the work root, `.git`, home defaults, or a machine-specific absolute path. Resolve requested logical paths against this fixed root and verify existence and real-path containment before reading. Fix the work root and Git target from the request and current Git state, independently of the instruction root.
2. Apply `link-targets/agents/skills/github/SKILL.md` when dealing with GitHub service/API. Apply `link-targets/agents/skills/external-operation-authorization/SKILL.md` for external effects, `link-targets/agents/skills/approval-request-workflow/SKILL.md` for permission/judgment, and `link-targets/agents/skills/external-posting/SKILL.md` for user-visible posting only when necessary.
3. Do not unnecessarily pour a large amount of raw comments / API responses into the main context. The use of subagents for acquisition, extraction, and organization is optional, and the main agent is responsible for final coverage and judgment.
4. Do not add a fixed taxonomy, fixed body schema, comment-ID ledger, persistent snapshot, or phase state, and if the state is suspicious, reread the history and converge to the same semantic state.
