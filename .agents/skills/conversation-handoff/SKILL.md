---
name: conversation-handoff
description: Create a conversation-centered handoff from a long, degraded, or evolving conversation to a fresh user-visible conversation, session, task, or thread while preserving intent, major pivots, obstacles, unresolved work, and user preferences. Use when the user asks to hand off, transfer, or continue work in a new conversation without losing context, including equivalent requests such as "move this to a new task", "引き継いで", "別セッションに移して", or "この会話を新しくして". If the user only remarks that the conversation is long, slow, confused, or degraded, recommend a handoff but do not create one unless they ask.
---

# Conversation Handoff

Move the current conversation to a fresh, user-visible conversation without losing its human intent or important history. Preserve the source conversation as a recoverable record.

## Operating principles

- Preserve the conversation, not a substitute code review. Explain why the work exists, what the user asked, what the agent did, what changed, where work stalled, and what remains unresolved.
- Match the language of the current conversation.
- Preserve important phases and causal links while merging repetition and omitting noise.
- Prefer durable references to plans, issues, commits, diffs, files, and URLs over reproducing their contents.
- Mention repository or process state only when it explains the conversation or a current obstacle. Do not produce a file-by-file change summary that the destination can recover from the workspace.
- Summarize observable actions, decisions, outcomes, and stated rationale. Never expose hidden reasoning or chain-of-thought.
- Redact secrets, credentials, tokens, cookies, private keys, and unnecessary personal data.
- Do not archive, delete, compact, clear, or otherwise mutate the source conversation.
- Do not create branches, commits, or worktrees solely for the handoff.

## Workflow

### 1. Establish the handoff scope

- Infer the destination focus from the user's request and the current conversation.
- Treat a clear request to move or continue the conversation as authorization to create the destination when the host supports it.
- If the user only remarks that the conversation feels slow, long, confused, or degraded, recommend a handoff but do not silently create one.
- Ask a question only when a missing choice would materially change which work is transferred.

### 2. Select one host adapter

Identify the current host from the system environment and available host capabilities. Read exactly one matching adapter.

| Host | Adapter |
| --- | --- |
| Codex | `references/codex.md` |
| Claude Code | `references/claude-code.md` |

- If the host is Codex, read `references/codex.md` and follow it.
- If the host is Claude Code, read `references/claude-code.md` and follow it.
- If the host cannot be identified or has no adapter, use the manual fallback in this file.
- Do not read adapters for hosts that are not in use.
- Resolve every relative path against this skill's directory, even when another skill or wrapper loaded this file.

### 3. Recover the conversation history

- Start from the current model-visible conversation.
- When the conversation has been compacted or its origin and major pivots are uncertain, use history-reading capabilities exposed by the selected host adapter, if available. Read only enough to recover the origin, major requests, direction changes, and unresolved obstacles.
- Check the live workspace, task state, or running processes only when necessary to verify a claim about what the agent did or why progress stopped.
- Mark uncertainty explicitly. Never reconstruct missing history as fact.

### 4. Write the handoff

Use the following structure, omitting only sections that are genuinely irrelevant:

```markdown
# Handoff: <short description of the continuing work>

## Why this work exists
<The user's original need, situation, and intended outcome.>

## Conversation trajectory
### <Phase or turning point>
- User: <request, correction, concern, or decision>
- Agent: <observable response, action, or decision>
- Outcome: <what changed or what was learned>

## Current understanding and focus
<What the work is now trying to accomplish and why.>

## Friction, dead ends, and discoveries
- <Obstacle or failed approach, whether it is resolved, and what should not be repeated.>

## User constraints and preferences
- <Only constraints or preferences established by the conversation. Mark inferences as inferences.>

## Open questions and pending work
- <Unresolved question, pending decision, blocker, or incomplete objective.>

## Relevant artifacts
- `<path or URL>` - <why the destination may need it>

## First response required from the destination
Restate:
1. why the work exists;
2. the current understanding and focus;
3. the unresolved points;
4. the proposed next action.

Do not use tools, edit files, or continue the work yet. Wait for the user to confirm or correct this understanding.
```

For the trajectory:

- Organize by meaningful phases or turning points, not by every message.
- Retain user corrections and changes of mind because they define the actual intent.
- Retain completed work only to explain what the user asked and how the agent responded.
- Record failed approaches when omitting them could cause the destination to repeat the same mistake.
- Omit greetings, acknowledgements, raw logs, repetitive tool output, and generic repository explanations.

### 5. Use transient staging safely

- Save the complete handoff as Markdown in the host operating system's temporary directory with a unique filename.
- Do not save it inside the repository unless the user explicitly asks for a durable project artifact.
- Treat the file as transient staging, not a durable backup.
- Run destination creation, delivery, and verification inside a cleanup flow that attempts to delete the temporary file whether the operation succeeds or fails.
- If deletion fails, report the residual path and do not claim that cleanup succeeded.
- If the temporary write fails, continue with direct or manual delivery without creating a repository file.

### 6. Deliver the handoff

- Follow the selected host adapter to create a genuinely new, user-visible destination when that capability exists.
- Include the complete handoff inline in the destination's initial prompt. Do not rely only on the temporary file path.
- Instruct the destination to produce only the required understanding response and then wait for the user.
- Verify destination creation and delivery before reporting success.
- Do not substitute a transcript-preserving fork, subagent, or background worker for a fresh user-visible conversation.

For the manual fallback:

- Do not claim that a destination was created.
- Return the complete copyable handoff.
- Give one concise instruction for starting a fresh conversation and pasting the handoff.

### 7. Close out the source conversation

- After successful direct delivery, report the destination briefly without repeating the full handoff.
- After manual fallback, return the complete handoff because no destination received it.
- Leave the source conversation intact as a recoverable record.
