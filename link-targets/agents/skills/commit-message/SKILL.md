---
name: commit-message
description: Apply formatting and history rules when creating or editing a Git commit message. It will not be activated for unrelated tasks.
---

# Commit message workflow

## Discovery contract

- Positive trigger: Create/edit a new commit message or amend target message.
- Negative trigger: Does not create a commit message, just reads the existing history.
- Conditional dependency: There is no additional dependency contract; the history of the current Git repository is checked directly.
- Failure mode: Don't assume defaults, check and stop if format or history basis cannot be determined.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

## Guide

Read this guide when creating or editing a commit message.
Includes message editing by `--amend`.

### Scope of application

The unit to check the rules and history is the Git repository you are currently trying to commit to.
When committing within a submodule, treat the submodule as the target repository. Do not mix in the parent repository's conventions or history; the same applies in reverse.

Messages generated or inherited from Git or existing commits, such as merge, revert, fixup, squash, and cherry-pick messages, are special because their format has meaning. They are excluded from the format determination below and are not rewritten to the default format unless explicitly instructed otherwise.

### Application order

If there are instructions from a higher level or explicit instructions from the user, those will take precedence. Otherwise, check in the following order.

1. Explicit commit conventions in the target Git repository (for example, `CONTRIBUTING.md`)
2. Commit history for author matching current Git user
3. Commit history for the entire target Git repository
4. Default conventions for this guide

### Check existing history

An author matching the current Git user is an author whose name and email both equal the current `git config user.name` and `git config user.email`.

The individual's history and the history of the entire repository are confirmed using the following criteria.

1. First, check the most recent 20 items.
2. If a consistent format is not clear, expand the scope of checks to a maximum of 50 items.
3. If there are fewer than 20 items, check the range that can be retrieved.
4. If the format is mixed, there is little history, or it is difficult to judge, proceed to the next step as "no clear convention".

Special generated and inherited messages are also excluded when determining history conventions.

### Default format

```text
<type>(<scope>): <subject>
```

`scope` is optional. `type` has the following basic candidates.

- `feat`: Added functionality
- `fix`: Bug fixes
- `docs`: Document change
- `style`: Cosmetic changes that do not affect behavior
- `refactor`: Structural changes not intended to add functionality or fix defects
- `perf`: Performance improvements
- `test`: Addition/modification of tests
- `chore`: Maintenance changes such as build and auxiliary tools

### Subject

- Write concisely.
- Essentially imperative and present tense.
- Do not add a period at the end.
- Use an expression that makes it easy to understand what has changed in the Subject alone.

### Body

Use a Body when the reason for or background of the change needs explanation. Instead of repeating the Subject, describe the following as needed.

- Why did we change it?
- Differences from previous behavior and state
- Important assumptions for judgment

### Footer

If necessary, include information to be recorded separately from the main text, such as related issues and breaking changes.

### Example

```text
docs(agents): add commit message guide
```

Use AngularJS's Git Commit Guidelines as a format reference. This guide's defaults do not include additional requirements such as a 100-character limit, a lowercase Subject beginning, or a strict `revert:` format.

Reference: <https://github.com/angular/angular.js/blob/master/DEVELOPERS.md#-git-commit-guidelines>
