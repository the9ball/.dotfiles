---
name: agent-output
description: Used to determine the code that can be copied in chat and the format of the text that can be passed to other agents. It does not trigger in unrelated conversations.
---

# Agent output workflow

## Discovery contract

- Host fallback: required

- Positive trigger: Outputs a copyable code or text to the chat that can be passed to other agents.
- Negative trigger: Normal explanation or conversation that does not require any special output format.
- Conditional dependency: There is no additional dependency contract.
- Failure mode: If the format contract cannot be read, stop and report instead of omitting the output.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

## Guide

Read this Guide before outputting copyable code or text relayed to other agents in chat.
Apart from external posting/delegation approval under `link-targets/agents/AGENTS.md`, this Guide determines only the format of the chat body.

### Copyable code

- A code block that users copy and use starts and ends with five consecutive U+0060 (backticks).
- Before sending, check the opening and closing counts, the language specification, and nesting support.

### Body to be passed to other agents

- Put the entire relay text, such as request texts, investigation instructions, and review viewpoints, inside a single five-backtick fence tagged `markdown`. Do not split the outer block by heading or section.
- Use 3 backticks for code blocks inside the body.
- Place only the main text to be delivered in the outer block; write any introductions, supplements, judgments, and notes outside it.
- The body text should be in a format that other agents can use without depending on the specific name of the destination.

<!-- reference-kind: policy-precedence; target: link-targets/agents/AGENTS.md -->
