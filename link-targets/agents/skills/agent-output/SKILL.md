---
name: agent-output
description: Used to determine the code that can be copied in chat and the format of the text that can be passed to other agents. It does not trigger in unrelated conversations.
---

# Agent output workflow

## Discovery contract

- Positive trigger: Outputs a copyable code or text to the chat that can be passed to other agents.
- Negative trigger: Normal explanation or conversation that does not require any special output format.
- Conditional dependency: There is no additional dependency contract.
- Failure mode: If the format contract cannot be read, stop and report instead of omitting the output.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

## Guide

Read this Guide before outputting copyable code or text relayed to other agents in chat.
Apart from `link-targets/agents/AGENTS.md`'s external posting/delegation approval, only the format of the chat body is determined.

### Copyable code

- The code block that users copy and use uses five consecutive U+0060 (backticks) both at the beginning and end.
- Check the start and end numbers, language specification, and nesting support before sending.

### Body to be passed to other agents

- For relay texts such as request texts, investigation instructions, and review viewpoints, put the entire text inside a single five-backtick fence tagged `markdown`.
- Do not separate the outer blocks by heading/section. Use 3 backticks for code blocks in the body of the text.
- Place only the main text to be delivered in the outer block, and write any introductions, supplements, judgments, and notes outside.
- The body text should be in a format that can be used by other agents without depending on the specific name of the destination.
