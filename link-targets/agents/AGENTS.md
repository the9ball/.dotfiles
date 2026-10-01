## Local project instructions

- When an `AGENTS.md` exists in a directory, read `AGENTS.local.md` in the same directory as additional instructions when that file exists.
- When an AI tool writes a script, use names with clear meanings for variable names, function names, command arguments, etc., and avoid using shortened names as much as possible.

## Protected paths

- `~/plans` is treated as a read-only protection path.
  - read / list is allowed.
  - create / edit / rename / move / delete is prohibited.
  - Ask the user for confirmation if changes need to be made.

## Code comment conventions

- When the AI adds or modifies code, attach the standard documentation comment for that language or project to every named method and function, whether public or private. Use XML document comments in C#, Javadoc in Java, docstring in Python, etc.
- Document comments should at least describe the role and purpose, and explain arguments, return values, exceptions, side effects, and preconditions as necessary. Even simple methods explain their role in one sentence.
- For complex branches, business rules, workarounds, and performance improvements, use regular comments in the relevant sections to explain “why they are necessary” and “which assumptions they depend on.”
- If the explanation changes due to implementation changes, update or delete existing comments.
- Do not write comments speculating on specifications or reasons that cannot be confirmed.
- Add a regular comment to unnamed lambda expressions and the like when they are complex.

## Precedence between skills and user instructions

- The procedures and completion conditions specified for the skill are treated as default. If the user explicitly gives different instructions for the current task and the target and scope of application can be uniquely identified, give priority to the user's instructions, including what is marked as "required" within the skill. For example, even if a skill requires passing a review, if the user specifies that “no review is required this time,” the review will not be included as a completion condition within that specified range.
- This priority relationship does not override higher-level instructions, execution environment privilege constraints, or safety constraints. If the target or scope of a user instruction is ambiguous, ask before skipping a skill step.
- User overrides/exemptions without specifying the period or repetition range are limited to the next application of the specified rule/process to the specified target set. Here, one time does not refer to a tool call or a conversation turn, but to a unit of work with the same target, purpose, and result. It does not expire when crossing turns or calling multiple tools to complete the same task, but it does not automatically inherit to the next iteration, another target, or a new review/QA application unit after the target has been substantially changed.
- Continuation specifications such as "during this task", "during this session", and "from now on" are valid only when the target rule/process, target, repetition range, and end condition are unique. "This task" refers to the task until the current purpose and scope of approval are completed, terminated, taken over, or substantially changed within the same user-visible thread. Continuation to a new task will only be allowed if explicitly recorded as a permanent instruction or valid standing approval.
- Continuation designation does not exempt external operations, destructive operations, action-time confirmations, protection paths, sandboxes, OS, OAuth, permissions, and other higher-level or security-necessary confirmations. Approved plans, goals, and valid standing approvals apply their recorded targets, operations, and durations, and are not reduced or expanded by this default.
- Regardless of the skill's distribution source, the skill's “no confirmation required”, “pre-approval”, “created/published/sent by default”, etc. will not be treated as satisfying the change range confirmation of this file, external operation confirmation, Git safety, protection path, or higher authority/safety confirmation. If a user's explicit approval is accurately recorded and reuse is permitted under the applicable rules, the prior approval may be reused only for the recorded object, operation, and scope.
- When a skill changes local files (including temporary files and artifacts that the agent can control where they are saved or retained), Git index/ref, connection service, or UI/app state, determine the target, operation, save/reflect destination, and exclusion at the relevant gate, and execute only within the approved range. Routing between skills, cleanup, and subsequent operations do not extend scope. Products whose individual names cannot be determined before execution are indicated by limited output roots (directories) or naming patterns.
- Exemptions such as "no review required" by the user apply only to the processes that are clearly targeted. Change range confirmation, external operation confirmation, Git safety, protection path, upper level rules, or authority/data integrity confirmation necessary for safety are not treated as exempt, and omitted steps are not reported as completed or passed.

## Interaction / Autonomy

- As a common contract for clarification, bounded research, and autonomous execution, the goal, scope, constraints, completion conditions, required permissions, and presence or absence of external operations are fixed before execution begins. Do not ask questions again about matters that can be determined uniquely from explicit instructions.
- Prioritize confirmation of important matters that can be easily determined by asking the user over guesswork or extensive exploration.
- When presenting a choice between approaches or making a recommendation, if materially different outcomes are possible and not evident from the options or earlier context, briefly explain in at most two sentences for the presented choice or recommendation what it means for the user in practice and the most decision-relevant risk or tradeoff a reasonable user would want to know. Providing this context does not itself request approval or change existing confirmation requirements for destructive or irreversible actions.
- Track loose ends, missing evidence, and target identity discrepancies, and make the target, scope, budget, and stop conditions of read-only investigations bounded.
- User non-response alone does not constitute approval of scope, permissions, or external operations. Do not introduce fixed time fallbacks and do not use elapsed time as a substitute for approval or judgment. Proceed to investigate as a condition-based fallback only if the subject and scope are fixed, the facts can be safely verified using read-only bounded research, and the research does not replace the user's preferences, approval, or authority judgments.
- Scope extensions, new permissions, irreversible operations, external operations, and items that require user preferences or design decisions should be stopped and checked instead of proceeding based on the passage of time.
- Autonomous execution will continue only if the goal, scope, constraints, and completion conditions are determined and within the approved range.
- In the future, if an auxiliary fixed time value (e.g. 5 minutes) is introduced, it should be treated as an adjustable operational parameter rather than a well-founded fixed threshold, and the reason for its introduction, safety conditions, and termination conditions should be clearly stated. However, the current contract does not have a fixed time fallback.

### UI and browser automation

- Regardless of `computer-use`, `browser-use`, or other names, the ability to manipulate the screen, keyboard, mouse, DOM, and browser (including via headless browser, CDP, Playwright, Selenium, MCP, plugin, and wrapper) is treated as a UI ability. Also includes CLI to operate the UI.
- Direct HTTP/API/CLI that does not operate the UI is not included in UI capabilities, and is given priority over UI capabilities if the purpose can be achieved.
- Before using UI capabilities, including read-only operations such as browsing, searching, and transitions, explain why the purpose cannot be achieved directly using HTTP/API/CLI, indicate the purpose, target, and scope of the operation, and obtain explicit approval. If a user-approved plan specifies the same UI capabilities, purpose, target, and scope of operation, the unit of work can be treated as pre-approved.
- `auto_review`, enabling tools/plugins, permission allowlists, or general planning consent that does not specify UI capabilities is not a substitute for explicit approval of UI capabilities or a pre-approved plan.
- Approval covers one unit of work, and repeated operations within the same purpose, target, and operation scope do not require separate approval. If any of those three changes, obtain approval again. "Allowed during this session" is valid only after the scope is fixed, and is not blanket permission for unspecified future work.
- Keep approval for UI capabilities separate from approval for external operations such as posting, updating, deleting, sending, and purchasing. Approval for UI capabilities alone does not authorize external operations, and approval for external operations alone does not authorize using UI capabilities.
- If the authorization channel or runtime returns expired, do not interpret it as authorization. This policy does not specify a numerical timeout, and a delayed response after the deadline will not revive the original request. Submit a new approval request to proceed.
- While waiting for UI approval and after it expires, bounded, read-only, direct HTTP/API/CLI investigations limited to the same purpose and scope can continue only as necessary to achieve the purpose. If the fallback materially changes the authentication principal, privileges, data scope, visibility, or external effects, disclose and obtain separate approvals. Fallbacks with additional privileges or external effects do not start based on the passage of time.
- Without a reasonable fallback, you can stop only the parts that depend on the UI and continue other approved work. By selecting timeout or fallback, pending UI requests will expire, and responses received later will only be treated as approvals for new requests.

- A common contract establishes the premises for clarification, bounded research, and autonomy. `execution-lifecycle-gate`'s execution contract, target identity, epoch, approval, review, commit, fixup, amend, autosquash, and external operation gate will be maintained within the scope of the same skill.
- Model-specific guides address only model-specific trends and supplements and do not redefine the same clarification rules as the common contract. It should not be used to override the requirements of system, user, role-specific contract, or skill.
- The common contract must not override Advisor research budgets, bounded research, `NEEDS_EVIDENCE`, or contracts in which the parent agent retains final judgment.

## Delegation to subagents

- For ordinary Codex investigation, implementation, and testing workers, explicitly specify model `gpt-6.1-sol` and reasoning effort `low` at startup and on continuation. Keep the primary chat's model/effort and Advisor model/trigger rules unchanged.
- For details of individual workflows, apply the corresponding skill runtime contract after skill discovery. If the skill cannot be resolved, do not rely on guesswork, stop the necessary work and report.
- Delegation does not expand authority or scope of approval. Complete “Check for thread mix-ups” first; before “Scope confirmation before file changes” is approved, only read-only work may be delegated. Changes by the delegatee are also limited to the approved scope. Do not run tasks that specify "one by one" or "in order" in parallel.
- When writing to the same work tree, only one person is responsible for editing each file. If it cannot be divided, the main thread will not touch the same range until the delegate is completed.
- Do not accept the report of the delegatee at face value. When coming to a conclusion related to facts such as file changes or verification results, check the differences and logs yourself to confirm the conclusion.

## Continuing agent sessions

- Reviewer and Respondent maintain separate contexts for each role and do not share each other's handles. Advisor output is treated as attributable advice, not as a proxy judgment.
- As a general rule, the actual investigation (search for the target, confirmation of specifications, behavior, and dependencies, reproduction, and evidence collection) will be delegated to the `scount` Evidence child. The root will focus on minimal confirmation of the target identity, epoch, and ledger, and physical verification of the packet, except when a Reviewer or Respondent verifies the target directly for independence.
- `scount` is a separate read-only role, does not modify files, workspaces, or ledgers, does not launch children, does not extend privileges, make external changes, or send externally. Returns the source, version or source hash of the fixed request, confirmation method, evidence that could not be obtained, and uncertainty in the packet, and does not finalize the judgment or review status.
- Reuse the child context only if the runtime indicates success in restarting the same target/epoch. If the target or epoch changes, the old packet/context/judgment will be invalidated and automatic transport/retry will not be performed. When there is no runtime, this reuse is treated as a contract for future adapters.
- Changes in revision are classified by the coordinator as `review_delta_classification`, and in the case of `REVIEW_PRESERVING`, only Advisor evidence of `CLEAR` that is linked to the source revision is referenced through an append-only inheritance edge. The packet/context/judgment is reacquired as revision-bound, and if the classification, edge, hash, and ledger cannot be verified in the actual execution context, it is invalidated.
- If a judgment role returns `NEEDS_EVIDENCE`, root fixes the request, permission range, budget, and termination conditions, and performs scount → root's verification/ledger record → explicit re-dispatch of the same epoch to the requesting role. If there is insufficient evidence or verification is not possible, maintain `NEEDS_EVIDENCE` or gate `BLOCKED`.

## Scope of work

- Limit changes to the extent necessary to achieve the goal.
- Even if you discover a problem that is outside the scope, it will not be automatically added to the list of fixes unless it is necessary to achieve the goal.
- Avoid unnecessary refactoring, cleanup, and format changes (YAGNI).
- Do not discard, move, or overwrite existing user changes.
- Dependency install, build, test, and exploration are limited to cases where the necessity can be explained from the execution contract, applicable skills, and completion conditions. However, the verification required for contracts, skills, and completion conditions and the exploration necessary to pin down the target will not be omitted.

## Task-specific guides

- The root of the shared instruction tree that contains the entity of this file is called `instruction root` to distinguish it from `work root` of the work target repository. `instruction root` is used only for resolving shared guides, not for Git operations or deciding what to change. Specific placement rules follow `link-targets/agents/guides/README.md`.
- The `instruction root`-relative `link-targets/agents/guides/` directory contains detailed guidelines that are read only when entering a specific task. Placement rules follow `link-targets/agents/guides/README.md`, and if an item in this file indicates an activation condition, read the corresponding file before starting work.
- Use-specific guides are treated as supplements to this file. If there is a conflict with this file, this file will take precedence.
- For GitHub service/API operations, `gh` or `gh api` is the standard route regardless of the execution environment. Authorization is read independently and conditionally when permission to execute an operation with external effects is required, approval-request workflow is used when explicit permission/judgment needs to be obtained, and external-posting is read independently and conditionally when dealing with user-visible external post text. Don't require approval-request to be loaded just for GitHub write.
- Aggregation of review information scattered in Issues/Pull Requests is performed only when the user or target task explicitly calls `review-consolidation`, and is not automatically triggered from normal Issue/Pull Request operations or review responses. The detailed contract will be left to the corresponding Skill.
- When posting issues, pull requests, review comments, etc. where other users can see them, do not include local environment-specific information in the body of the post unless explicitly requested. Detailed posting contract will be left to `external-posting` Skill.
- If a skill's runtime contract contains conditional dependencies that cannot be resolved, do not omit them; stop the work fail-safe instead of guessing.

## Scope confirmation before file changes

- The basic principle is that “edits may be made without prior approval if only the changes made by the Codex can be safely undone and restored without loss of the state before the start of the session.”
- Files tracked by Git in the project (the directory Codex is working with) may be edited without the user's prior approval, as long as you can ensure that there are no uncommitted differences from before this session.
- New files created by Codex within the current session may be edited without prior user approval.
- Get user approval before editing if any of the following apply:
  - Files outside the project.
  - Files that are not tracked by Git that exist before the session starts.
  - If the file being edited contains uncommitted differences that were not added in this session.
- If Skills, `AGENTS.md`, or other applicable instructions specify otherwise how to handle files, those instructions will take precedence.
- During work, if the agent detects a change it did not make, made by another session, the user, an external tool, etc., interrupt any work that may conflict with or interfere with that change, report it to the user, and confirm how to proceed.
- If confirmation is required before editing, list the path of the file to be changed, a summary of changes for each file, and exclusions in the same message and obtain explicit approval. If the approval range is exceeded, re-approval will be obtained.
- If the scope of changes is clearly specified in the approved plan, reconfirmation is not necessary.
- “One by one” and “in order” mean changing, verifying, and reporting each item before moving on to the next.
- When adding a new file, moving, renaming, or deleting it, or changing its usage, storage location, or target range, normal range checks are applied, regardless of whether it can be edited. For external disclosure, push, and external transmission, separate confirmation is applied before external disclosure. If there are more specific project-specific rules, give priority to them.

## Authorization boundaries for external operations

- Push, creating and updating PRs/issues, sending/publishing/sharing/deploying to external services, changing permissions, and changing external data should only be done with explicit user instructions. Approval of file changes does not serve as approval of external operations.
- Do not extend external effects beyond the scope of targeted and authorized operations, and do not interpret consent to procedures or arrangements as approval for public operations.
- The external-operation-authorization skill owns detailed boundary, last-minute confirmation, consumption, retry, read-back, and result recording. Apply the same skill only when an external operation occurs, and stop if it cannot be resolved.


## Git commit policy

- A branch can be created when a task requires it, at the explicit direction of the user, or when required by repository-specific rules. Because worktrees involve additional working directories and state management, they cannot be created solely at the agent's discretion; they require explicit instructions or approval from the user. Prioritize repository-specific branch operations, direct master operations, and explicit push rules.
- Do not perform destructive Git operations, history rewrites, or force pushes without explicit instructions.
- When creating or editing a new commit message (including `--amend`), discover `commit-message` Skill and apply its runtime contract. The unit of determination for scope, rules, and history is the Git repository that is currently being committed, and information about parent repositories and submodules should not be mixed.
- Follow the Guide section of `commit-message` Skill for message format/history confirmation order, expansion from the most recent 20 to the maximum 50, and fail-safe when it is unclear.
- When modifying, canceling, or porting commits to another branch, consider using `--fixup`, revert, cherry-pick, etc. that suit your purpose.
- If Git, formatter, or lint generate a large amount of changes outside the scope, they will not be included automatically and will follow the scope control of `git-operations` Skill.
- This common rule for Git, commit, and verification deals with the scope of changes, operational authority, and verification boundaries, and leaves commit message format and history rules to the `commit-message` Skill.

## Permission errors and alternatives

- For errors caused by permissions, authentication, or sandboxes, do not silently switch to another route; instead, indicate the required operation, target, and reason and obtain confirmation. The runtime contract of `git-operations` Skill applies to Git's `index.lock` exception, read-only cause confirmation, privilege elevation for the same command, and lock deletion conditions.

## Read scope for AI reviews

- For AI reviews with Advisor or explicit read scope contracts, apply the advisor-review Skill self-contained contract. If the skill cannot be resolved, stop.


## Implementation plans and runbooks

- When creating, updating, and reviewing implementation plans or runbooks, apply the implementation-planning skill's self-contained contract. If the skill cannot be resolved, stop.


## Check for thread mix-ups

- Only if the request is based on previous work/judgment/results that are not mentioned in this conversation, and the target or expected state cannot be determined by the request alone, will the recipient be confirmed before starting. It will not be triggered by a new self-contained request or by simply changing the topic. If in doubt, place it on the side that won't activate.
- If it is not activated, proceed with the normal response/procedure without explaining the judgment of this confirmation rule.
- Do not use the tool (including changing files, executing commands, or sending externally) until you receive a confirmation response. Don't go looking for candidate threads yourself.
- When checking, only the following sentence is output. Do not include any introduction, supplementary information, or explanation of the reason, and do not mention the name of the request (file, function, ticket number, etc.).
  - Exact output: `この会話にない直前の作業を前提としているように見えます。このスレッド宛で合っていますか。`
    English gloss: “This request seems to assume immediately preceding work that isn't in this conversation. Is it meant for this thread?”
- Once the mix-up is confirmed, stop working in this thread. Ask the user to make the request again in the correct thread. If the user wants to find that thread, guide them to open a separate session to search for it.
- If the answer is “Yes,” do not re-check as long as the target and premise remain the same.
- This confirmation is performed before "Scope confirmation before file changes". A reply to the thread confirmation does not serve as change approval.
