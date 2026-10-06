---
name: code-commenting
description: Before adding or modifying program source code, including scripts, new files, tests, and comment-only source edits, apply required documentation comments and regular-comment conventions. Also use when explicitly asked to review or revise code comments. Does not trigger for unrelated read-only investigation, Issue maintenance, or prose-only editing.
---

# Code commenting

## Discovery contract

- Positive trigger: Add or modify program source code, including scripts, new files, tests, and comment-only source edits; or explicitly review or revise code comments.
- Negative trigger: Unrelated read-only investigation, Issue maintenance, or prose-only editing.
- Conditional dependency: None. Formatting and commit-message workflows retain their own triggers and contracts.
- Failure mode: If this Skill or the applicable comment convention cannot be resolved, stop the dependent work fail-safe and report; do not silently omit required comments.

## Runtime contract

Read and apply the Guide before the first source-code change, and retain it through final verification. The shared global instructions explicitly route code changes here; automatic host discovery is not a prerequisite. This Skill owns comment content and purpose, not formatting tools, test creation, or commit-message formatting.

## Guide

- Distinguish two kinds of comments: documentation comments state the role and contract of a named method or function for its callers; regular implementation comments explain information the code itself cannot show. The required role comment for a complex unnamed construct is described below.
- When the AI adds or modifies code, attach the standard documentation comment for that language or project to every named method and function, whether public or private, including test methods and functions. Use XML document comments in C#, Javadoc in Java, docstring in Python, etc.
- Document comments should at least describe the role and purpose, and explain arguments, return values, exceptions, side effects, and preconditions as necessary. Even simple methods explain their role in one sentence.
- Use regular comments next to the relevant code to explain why a non-obvious approach is necessary, why an apparent alternative is unsuitable, and which constraints, assumptions, compatibility requirements, business rules, workarounds, or performance tradeoffs it depends on. Avoid regular comments that merely narrate obvious code behavior.
- Test methods and functions follow the same documentation-comment rules. Express expected behavior through test names and assertions; do not restate the assertions in regular comments. This guidance does not itself require adding tests.
- Keep historical change context, such as previous behavior and what changed, out of code comments. When it needs recording, it belongs in commit messages/history. Rationale that remains true for the current implementation may also remain next to the code even when a commit message explains it.
- If the explanation changes due to implementation changes, update or delete existing comments.
- Do not write comments speculating on specifications or reasons that cannot be confirmed.
- When an unnamed lambda expression or similar construct is complex, add a regular comment stating its purpose or intent in the surrounding logic, as a documentation comment would for a named function. Explain why the construct exists or what role it serves rather than enumerating operations or structure that are already apparent from the expression. This requirement remains mandatory; the guidance against narration does not remove it.

Before completing the code change, check the authorized change scope against these requirements. Preserve applicable documentation comments, verify required role comments for complex unnamed constructs, and check that changed comments describe the current code accurately. Do not turn this check into unrelated comment cleanup.
