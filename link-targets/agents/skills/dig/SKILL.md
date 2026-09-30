---
name: dig
description: >
  [Used only when explicitly designated] Only when the user explicitly specifies `$dig` or `/dig`, dig into the assumptions behind plans, designs, and technical decisions one question at a time, then confirm common understanding with recommended answers and reasons.
  Do not use this skill for ordinary consultation, one-off questions, or implementation requests with settled policies.
---

# dig

Use this mode only when explicitly started with `$dig` (`/dig` in Claude Code).
If it is read without explicit designation, this content is not applied and the process returns to the normal flow.

## How to proceed

- View the target as a design tree and update dependent undecided items for each answer.
- Dig deeper into one branch without expanding further until no new insights emerge.
- Once the branch you're digging is resolved or no new insights are gained, choose the next undecided item that has a large impact and is the basis for other decisions.
- Facts that can be discovered by examining the environment should be checked by yourself first using read-only operations only.
- Leave questions that depend on the facts under investigation for later, and move on to branches that don't depend first. If there are no independent branches and all remaining issues are under investigation, clearly state that they are pending investigation and the unresolved issues, and continue the investigation. If the investigation cannot be performed, indicate the reason and any necessary next instructions.
- Ask users only about choices and tradeoffs.
- Ask only one question at a time, and be sure to include importance, options, recommended answers, and reasons.
- Just before posing a question, qualitatively estimate how much exploration remains, using the currently visible design tree and dependent unresolved issues as the basis. Consider importance, dependencies, and depth, and display the value at the beginning of the question block as a rough guide. Do not use fixed increments, fixed weighting formulas, calculations that use only the number of questions as the denominator, or a separate progress ledger.
- If there is not enough information to roughly estimate the entire design tree and compare against it, display `残り: --%` instead of forcing a number. Early in exploration, undiscovered branches may remain, so do not treat only the currently visible branches as the entire design tree or estimate the remaining amount from them. Once the overall shape can be roughly estimated, a number is allowed; this does not require exhaustively listing the major branches, and the existing depth-first approach remains in effect. If dependencies or depth are unknown, use `--%`. New branches or dependencies may increase the estimate or return it to `--%`; a monotonic decrease is not guaranteed.
- The question being posed will be treated as unresolved. Interim decisions adopting recommendations will not be counted again as material outstanding matters, in accordance with existing treatment. The remaining amount is only used as a guideline and will not be used as the basis for additional questions or termination conditions.
- Ask questions in the following format. Add as many options as the decision needs.

```markdown
### ❓ Q[number]: [question text]

残り: ~[概算]%

[Why this question is important]

- **A** — [Choice]
- **B** — [Choice]
- **C** — [Add if necessary]

**推奨: [A/B/C]** — [Reason]
```

If it cannot be quantified, display `--%` instead of `~[概算]%`.

## dig-log

- While deliberating, retain not only the final decision but also the reasons, premises, concerns, important changes, withdrawals, redefinitions, and unresolved matters necessary for the decision so that it can be converted into a dig-log later. It does not create a fixed taxonomy or separate persistent state.
- The normal closing summary maintains the existing concise format. Generate a dig-log only when the user explicitly requests it. Creation can be done during dig, but if you are only asked to create it within a conversation, it will not be saved.
- For requests that include storage, such as 「dig-log を書く」 ("write the dig-log"), the storage destination is estimated if it is unique from the context, and confirmed if it is ambiguous. Writing to a storage destination is performed as a normal operation after dig is completed, and follows the authorization / posting contract applicable to that destination and the rules of the target repository, including local files.
- dig-log does not require a fixed schema, but instead semantically compresses the final decision at that point and the reasons, assumptions, concerns, important changes/reversals, and unresolved issues needed to understand the decision in subsequent work. The purpose is not to save the entire conversation.
- When saving, ensure a resolvable association between the target artifact and dig-log through the normal path of the destination, making it discoverable from subsequent work. If this cannot be guaranteed, do not save based on a guess; instead, perform the necessary checks or report that it can't be saved.
- Give the dig-log a stable identification marker. In Markdown/GitHub, `<!-- DIG-LOG -->` is used as a standard example, and the specific method of marker/pointer is left to the destination.
- Folding, etc. is a destination-specific presentation. `<details>` on GitHub is an example that can be used, but it is not required for common contracts.
- Dig-log is not a source of truth, but a historical artifact that records the decisions and reasons at that time. Current authoritative artifacts follow existing work-plan/artifact ownership contracts and do not infer if there are multiple or unknown candidates.
- In subsequent work where it is determined that a discoverable dig-log exists for the target artifact, refer to it through the normal route if the design intent is relevant. Full search of hidden history etc. is not required.
- Don't make conversation thread sharing a dig-specific save/handoff feature. Delegate to existing conversation handoff/thread sharing responsibilities if necessary, and do not define inheritance of approvals, permissions, or unfinished work in dig.

## Continuation and termination

- 「続けて」 ("continue") during dig is treated as an instruction to continue asking the next question.
- For instructions such as 「進めて」 ("go ahead") that can be read as either continuing the question or transitioning to implementation, confirm the intention only once as to which is meant. If this confirmation may lead to moving on to implementation, also state the important unresolved issues and their impact, so that it doubles as the confirmation of the move to implementation.
- If the user answers 「わからない」 ("I don't know") or 「任せる」 ("I'll leave it to you"), the recommendation is accepted as a tentative decision, recorded as a premise or unresolved, and proceeds to the next branch. Do not rephrase the same point and ask the question again.
- If you are asked to implement something with important unresolved issues remaining without going through this intention confirmation, indicate the unresolved issues and their impact, and confirm once if you want to proceed with implementation with the remaining issues.
- When the user explicitly says 「digを終了」 ("end dig"), 「質問を打ち切る」 ("stop the questions"), or 「未解決のまま実装へ移る」 ("move to implementation with issues unresolved"), the unresolved issues will be summarized and dig will be closed.
- If there are no important undecided items (other than those treated as tentative decisions) and the next questions do not provide new insights, confirm common understanding and close.
- At the end, briefly summarize what has been decided, unresolved matters, and remaining assumptions in the following format.
- Even if there is no applicable item, the heading should not be omitted and should be written as `- なし`.

```markdown
## まとめ

### 決まったこと
- ...

### 未解決事項
- ...

### 残る前提
- ...
```

## Authorization and delegation

- dig's common understanding confirmation does not replace plan approval or scope confirmation before file changes.
- Even after the user explicitly confirms that they want to proceed with implementation, the normal approval gates and rules of the target repository are followed.
- Investigations and confirmations during dig are read-only, and operations that involve changes are not performed.
- When delegating investigations to subagents, follow `AGENTS.md`'s delegation rules and host-specific authorization procedures.
