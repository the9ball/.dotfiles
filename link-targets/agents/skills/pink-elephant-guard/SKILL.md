---
name: pink-elephant-guard
description: >
  [On trial. Not triggered implicitly. Only used when the user explicitly names $pink-elephant-guard]
  Use when writing for readers who did not see the conversation, such as in commit messages, PR text, ticket comments, or messages to colleagues. It prevents contextless statements that rely on readers reconstructing rejected, deleted, or corrected assumptions, such as "I decided that this was unnecessary" or "I decided not to do it this time."
  Do not use for documents that must preserve rejected hypotheses, turns, or failure paths (such as ADRs, minutes, postmortems, review replies, and `*.history.md`), or for notices required by law, contracts, safety, medicine, or accessibility.
---

# Pink Elephant Guard

## Purpose

Ideas that are rejected in a conversation do not exist for readers who do not share in the conversation.
If you write a negative expression based on this premise in a work product, an unfounded context suddenly appears to the reader.

This skill is for removing such descriptions from the work product or reconstructing them in a form that the reader can understand.

## Core principles

**The defect is not “touching what has been rejected,” but touching it while dependent on a context that the reader cannot recover.**

Therefore, deletion is not the only solution. Select one of the following depending on the purpose of the document.

- If it does not belong in the text (commit message, etc.): **Delete**
- If it is to be described (design judgment, etc.): **Do not delete it, but write it in context as an option**

This skill is not intended to reduce the amount of currently valid information.
Currently valid restrictions, warranty scope, compatibility, migration procedures, and statements to prevent misreading are not covered, even if they are in negative form.

## Scope of application

Any text that passes to a reader who does not share the context of this conversation.

- commit message, PR/Issue text, review comment
- Ticket comments, wikis, shared notes, and explanations for colleagues
- Release notes, explanations for users, UI text/labels
- Copy for viewers, dialogue, and the descriptive parts of image/video generation prompts

Even if the reader is oneself, the context is no longer shared over time.
Don't use the fact that "only you read it" as a reason for exemption.

Control instructions passed to the generative model are not covered.
Negative forms such as “no text,” “no person,” and “no watermark” do not describe past proposals; they define current output requirements, and removing them would make the deliverable violate those requirements.

## Not applicable

Judgments are made by section/description, not by the entire document.
This is because a section for recording the process and a section for external explanations may coexist in one document.

It should not be used in the following descriptions.

- Clauses/descriptions in which it is a requirement to preserve rejection hypotheses, policy changes, and failure paths
  (This includes ADR, minutes, postmortems, `*.history.md`, memos for continuing work, conversation handover documents, etc.)
- In a reply to review feedback, when the reason for not adopting the suggestion is itself the content of the reply.
- Comparison of plans A and B, audit records, cause analysis
- Necessary displays related to laws, contracts, safety, medical care, and accessibility, currently valid restrictions and warranty scope,
  Compatibility, migration instructions, and security information. Below, these are collectively referred to as **required information**.
- Non-use appeal explicitly requested by the user (must include "decaffeinated", etc.)

Even within the same document, sections of external explanations that do not fall under the non-applicability exceptions are inspected as usual.

When there are conflicting decisions, prioritize from top to bottom.

1. Required information
2. Latest facts and specifications available
3. The current state last determined by the user. Latest user instructions update previous specifications
4. Content specified by the user to be displayed in the deliverable. However, this is limited to cases that do not contradict items 2 and 3.
   If there is a conflict, do not output it and check which one to take.
5. Previous plans and changes

## Judgment

Deciding whether to write or not is a two step process. Do not change the order.

### Stage 1: Grounds determination

> **From only the latest verifiable materials (differences, tickets, specifications, decision records, the latest user-confirmed state),
> can you support this entire claim (state, change, reason, cause and effect)?**

Do not count the finished text as evidence. If you base your judgment on the sentence you just wrote, the reasoning becomes circular.
Do not rely on memory of the conversation either. A judgment that relies on memory produces the very mistakes this skill is trying to prevent.

Look not at whether the target word exists, but at whether the entire claim is supported.
Even if "parallel processing" appears in the diff, if the reason "to avoid conflicts" appears nowhere in the materials,
that claim is not supported.

**If it fails, delete it or ask the user. Do not try to save it by adding context.**

### Stage 2: Self-sufficiency determination

For claims that pass the first stage, determine the following:

> **Using only the finished text and the materials the reader can consult, can a reader who did not see the original conversation
> understand the premise, basis, and conclusion?**

**In case of failure, supplement by using only confirmed current information.**
Do not supplement with information derived from past conversations that have been rejected or corrected.

### Verification destination

The targets of the first stage are divided according to the type of claim.

- **Fact of change** (what was added/deleted/changed): Check by difference
- **Reasons/Causes/Design Judgments**: Tickets, specifications, design documents, decision records,
  and the latest explicitly confirmed user state that can be seen directly in the current conversation.

Past drafts reconstructed from memory or speculation will not be included in the comparison.
Only the most recent explicit instructions that can be directly verified are allowed to be included.

| Type | Example | Treatment |
|---|---|---|
| Deleted (existed → disappeared) | `remove unused retry wrapper` | Leave. Supported by differences |
| Not added (suggested only in conversation and rejected) | "The retry mechanism was judged to be unnecessary, so I decided not to add it" | Do not include it; the only basis is the past conversation in which it was rejected |
| Currently valid design constraints | "Do not silently suppress concurrent execution; leave its handling to the caller" | Include only if supported by specifications, tickets, code descriptions, or the latest explicit user-confirmed state |

## Procedure

1. **Define your audience and materials.** Decide in advance who your intended audience is and what materials they can refer to.
   If there are multiple readers, use the reader with the least information as the standard.
   (Example: PR reviewers can see tickets, but maintainers who only read the history later cannot.)
2. **Separate.** Divide the conversation into “contents that are currently finalized,” “process of rejection/correction,” and “content the user specified to be stated explicitly in the deliverable.”
3. **Create a draft based only on the current state.** Don't mix negative instructions such as "don't write X" in your brief.
   Construct it in an affirmative form that holds true even without X.
   Do not include reasons derived solely from past conversations that were rejected or revised, or old proposals.
   However, constraints and reasons that are necessary for the current judgment and that pass the first-stage basis judgment should be included.
   However, control instructions that define current output requirements are not subject to this restriction.
4. **Judge.** Apply the first stage (foundation determination) and then the second stage (self-sufficiency determination) to each claim in the draft.
   For code, first identify the set of changes described by the artifact, then consult the diff.
   - commit: distinguish between staged diffs, unstaged diffs, and untracked files
   - PR: Use base–head diffs
   - Existing commit: use appropriate range
5. **Correct and check again.** Delete claims that failed the first stage or ask the user about them.
   For areas that failed in the second stage, supplement with only confirmed current information.
   If the structure of the section itself is based on the old proposal, reorganize that section from step 3.
   If it is a one-sentence problem, local correction is sufficient.
   After modification, check whether the original requirements and the required information defined as non-applicable remain.
   If anything is missing, return to step 3.

## What to pick up during inspection

Pick up only expressions that originate from content that was rejected or corrected in the conversation.

- Dismissal words, their paraphrases, hypernyms, euphemisms
- Reason for deletion, explanation of change (「以前は」 “previously”, 「代わりに」 “instead”, 「今回は見送った」 “decided not to do it this time”, 「不要と判断した」 “judged unnecessary”)
- Is the absence of a rejected proposal the subject of the headline, opening, or conclusion?
- In images and videos, outlines, shadows, containers, placeholders of deleted objects, and old lines that remain in the audio

Negative expressions that are currently valid restrictions, specifications, or warnings will not be picked up.
It also does not pick up control instructions to the generative model.
Visual inspection for images and videos is not applicable when targeting code or text.

Media whose actual files have not been verified will not be reported as verified.

## Where do rejected proposals go?

Retain records covered by the non-applicability exceptions according to their respective requirements. Do not include content outside those exceptions that has meaning only as past history in the main text or external explanations.

- For runbooks and implementation plans, record an item in `<stem>.history.md` only when it meets the conditions in “Runbook/plan history management” of `link-targets/agents/skills/implementation-planning/SKILL.md`
  (for example, a substantive withdrawal or reversal of a procedure or policy). Do not record items that do not meet the conditions.
- For other artifacts, do not create a place to keep the details on your own. If keeping them is necessary, ask the user.

On the other hand, **constraints and reasons necessary to understand and implement the current decision** are left in the deliverable even if they mention the rejected proposal.
In that case, write the context in a way that the reader can restore it as an option.

## Completion conditions

- No phrases, paraphrases, or negative forms derived from the rejected or corrected conversation history remain outside statements covered by the non-applicability exceptions.
- There are no reasons for deletion, explanation of changes, or emphasis on absence that are based only on past conversations that led to rejection.
- The heading, introduction, and conclusion address the current purpose.
- Each claim has passed the first stage (foundation determination), and the completed text is not used as a basis for that determination.
- The context supplemented in the second stage (determination of self-sufficiency) consists only of confirmed current information.
- Regarding code, we actually verified the change set identified in step 4.
- After modification, compare against the original requirements and required information, and confirm that inspection did not omit them.
- Not reporting unconfirmed media as inspected
- Deliverables do not look like deletion traces and are naturally established with only the current contents.
