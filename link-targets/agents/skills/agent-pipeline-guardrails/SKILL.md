---
name: agent-pipeline-guardrails
description: >
  [For Claude Code only. Do not use from other agents/tools]
  Use this skill in development workflows involving the Architect, Implementer, Reviewer, or Investigator personal subagents under ~/.claude/agents/. It provides guardrails against directing plan rewrites or treating generated code as production without the user's explicit approval. Always refer to it when calling any of these four agents, relaying feedback between agents (especially to Architect), deciding who will implement (the orchestrator, Implementer, or Codex via the user), routing minor work directly to Implementer or through Architect planning, choosing whether a review goes to Reviewer or Claude, or performing a final review before creating a PR. Implementer does not start automatically; the user chooses who implements, and can choose Codex.
---

# Agent Pipeline Guardrails

Architect / Implementer / Reviewer / Investigator are personal subagents (`~/.claude/agents/architect.md` /
`implementer.md` / `reviewer.md` / `investigator.md`). An automation skill dedicated to orchestration was intentionally not created
(auto-chaining the whole pipeline would lose the human approval points along the way). Instead of automation, this skill
collects the minimum confirmation rules that the orchestrator (this session itself) should follow.

## Rules to follow

1. **Give the Architect an instruction to rewrite the plan only after obtaining the user's explicit approval.**
   - When passing feedback from Implementer/Reviewer/Investigator to the Architect, do not simply forward it. Present the feedback content
     and the Architect's proposed correction (if any) to the user, and after obtaining approval,
     give an unambiguous instruction such as "revise the plan with this content".
   - Don't settle for vague requests such as "Please handle this" or "Do as you see fit." The Architect is defined to not rewrite the plan without an explicit instruction, so even if the orchestrator skips obtaining the user's approval first, a major accident is unlikely (the Architect will stop at making a suggestion). Even so, proceeding without confirming the user's intent is still a problem.

2. **Obtain the user's explicit judgment before treating generated code as adopted for production.**
   - Product constraints prohibit including AI-generated code in production. Temporary code for debugging may be permitted case by case, so always present the final implementation report (production/debug classification and changed-file list) to the user and confirm their acceptance before proceeding.
   - **This gate applies regardless of who implements the change or its size or mode.** Do not omit it when the Implementer makes the change or when the orchestrator makes a one-line change through the pass-through gate (素通しゲート); the product constraint is independent of both the implementer and the change size.
   - If it is rejected, follow the reported "How to revert if rejected" (use `git checkout`/`restore` for existing files;
     delete new files).

3. **If in doubt, stop.**
   - If you are unsure about what has been approved, don't skip confirmation and ask the user again.

4. **Do not take feedback at face value; check unclear points yourself before relaying it.**
   - Before relaying feedback from Reviewer/Implementer/Investigator to another agent (especially Architect), read it
     and check that you really understand it. Do not fill in parts that seem ambiguous, contradictory, or weakly supported by interpreting or summarizing them in a convenient way.
   - If something is unclear, ask the user first (before relaying it to Architect or another agent). If you skip asking the user and relay a guess,
     that guess is carried straight into the plan or code.

## Whether to start the Implementer

**Implementer does not start automatically.** There is always the option of asking Codex to implement the same change, and
the user decides which to use, so do not route work to the Implementer on the orchestrator's judgment alone.

- **The user has explicitly designated an Implementer** → Pass it to the Implementer (determine below whether to pass the Architect first).
- **No designation** → If it falls under the "pass-through gate (素通しゲート)" below, the orchestrator implements it. Otherwise, before implementation starts, ask the user to choose among: the orchestrator implements it; it is passed to the Implementer; or a plan is created for the user to pass to Codex. Do not decide on the user's behalf.

### Whether to go through Architect first (routing tasks for which there is no plan yet)?

For tasks without a plan, decide whether to route through the Architect based on the task's scale.
If you make every task create a plan file, even a one-line change would require a runbook first, which is highly inefficient. Decide in the following order:

1. **All four conditions of "pass-through gate (素通しゲート)" below are met** → Implemented by the orchestrator itself without passing through the pipeline.
2. **The user has designated the Implementer, and conditions 1 to 3 of the pass-through gate (素通しゲート) (scale, no design decision, verification
   completed by build/test) are met** → **Skip Architect and pass it directly to the Implementer**
   (the Implementer's "direct task mode"). No plan file is created. When calling, do not pass a plan file path;
   pass the change itself as the task.
3. **None of the above** → Create a plan in Architect as before, get user approval, and then proceed with implementation
    (Do not omit this order). Use this route as a guide when design judgment is needed, work spans multiple layers or files, the impact scope is unclear, or side effects such as regenerating generated files or changing a schema are involved.
    Once the plan is complete, the user again decides who implements it: the orchestrator itself, an Implementer, or Codex at the user's direction.

- **If in doubt, lean toward Architect first** (the same as Guardrail 3). However, if the user has clearly said "it is minor, so just do it directly",
  respect that decision.
- The Implementer has its own start conditions (`implementer.md`, "Contract requirements for direct task mode"). If the task is later found not to meet them, the Implementer will not start and will recommend routing it through the Architect. After receiving that report, restart with the Architect.
- Every route must pass through the implementation approval gate (Guardrail 2). A lightweight path skips planning, not the user's decision to accept or reject the implementation.

### 素通しゲート (Pass-through gate): conditions where you can implement it yourself without going through Architect/Implementer

Only if **all** of the following conditions are met may the orchestrator implement the change itself with Edit/Write, without going through the pipeline.
If even one is not met, ask the user who will implement it (whether to go through Architect first is decided by the routing above).

1. It is expected that changes will be made in two files or less, and that the total number of added and changed lines will be within roughly 30 lines.
2. It involves no design decision: the change is one of following an existing pattern, fixing an obvious error, or changing wording, constants, or configuration values.
3. Verification can be completed by running a build/test or visually checking the differences (there is no need to start the environment and follow the behavior).
4. The user has not explicitly named the Architect or the Implementer. If they have, follow that regardless of size.

If in doubt, lean toward routing through the pipeline. However, repeatedly routing even small fixes to Architect "because I was unsure" makes plan creation (Opus) cost more than the actual work. Actually apply the four conditions above; when you pass a change through, report in one line that you judged it minor and fixed it directly, so the user can follow the decision.

**The implementation approval gate is not omitted even when the change is passed through.** Code written by the orchestrator itself is also AI-generated code,
so the production-adoption decision in Guardrail 2 (presenting the production/debug classification and the changed-file list, and confirming acceptance) is needed in the same way.
Only the Architect's planning and the delegation to the Implementer can be skipped; the user's approval cannot be omitted.

## Whether to call a reviewer

The target of `reviewer` review is the worktree diff, and **the implementation actor does not matter**. This includes changes made by the Implementer, changes made by Codex at the user's direction, and changes made by the orchestrator itself.
However, investigating the cause of a defect or bug report in existing code is not `reviewer`'s role. If you need to start the environment and trace the behavior,
use `investigator`; otherwise the orchestrator investigates it itself.

Since `reviewer` runs in Opus and rereads the differences and related code, writing a report for a small change can cost more than the change itself. You may omit the review in the following cases (leave a line explaining the omission).

- All verifications by the implementation side have passed, and the diff is 1-2 files and low risk (such as a change to a setting value or log output
  that does not add logic branches)

Conversely, in the following cases, call `reviewer` even if the scale is small.

- Covers security, authentication, authorization, and handling of external input
- The implementation side reports a deviation from the plan, or skipped some verification
- This change is intended for production use (not temporary code for debugging)

When a user requests a review, call the Reviewer regardless of the change's size. This omission criterion applies only to the orchestrator's default behavior and does not override explicit requests.

## Final review before PR creation

Even when a request is made for a "final review before PR," only Claude runs the review. **The orchestrator does not send review requests to Codex.** Requests to Codex are made by the user.

- **Claude's review**: Follow the criteria in "Whether to call a reviewer" above. When calling `reviewer`,
  call it as `Agent` (`run_in_background: false`), and if the omission criteria apply, the orchestrator performs the review itself.
- **If you want a second opinion from Codex**: There is no way for the orchestrator to start Codex. If you judge it necessary,
  tell the user so, together with the perspectives you want checked, and have the user request it from Codex. If the user pastes the results, reconcile them with Claude's review and combine them.
- **When combining**: Compare both sides' findings and sort them into (a) findings raised by both (high confidence), (b) findings raised by only one side (state the source),
  and (c) points where the two disagree, and produce one comprehensive review. Do not casually treat one side as correct. Present each disagreement
  with "whose claim it is" preserved, and leave the final decision to the user.
- **No corrections in the final review**: This is only a review. Corrections based on the findings are made separately, and whether the result is
  adopted for production is decided by the user (the same as the other guardrails of this skill).

## Why

This guardrail clarifies the wording of the prompt (what constitutes “approval”) but cannot enforce it technically. Architect has previously mistaken an ambiguous request such as “Please respond” for permission to rewrite (found and fixed in testing on 2026-07-10), and the orchestrator faces the same risk.
Where permissions can be technically restricted (such as available code-editing tools, working-directory scope, or the default model), the `tools` and body rules in each agent definition already address them. This guardrail covers only what those rules cannot fully address: interpreting the meaning of words.
