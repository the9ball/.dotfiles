---
name: structured-data
description: Used when reading structured data such as JSON as a value or hierarchy. Does not fire for unrelated text searches.
---

# Structured data workflow

## Discovery contract

- Positive trigger: Interpret the structure of JSON or extract values/hierarchy.
- Negative trigger: Only displaying full text or running a normal Markdown search, without interpreting structure.
- Conditional dependency: There is no additional dependency contract; only the result of a structured parser is used.
- Failure mode: If the structured parser cannot interpret it, stop and report instead of falling back to text guessing.

## Runtime contract

Only when this Skill is discovered, the Guide section below will be applied as a normative contract. Load conditional dependencies only when necessary. If a dependency cannot be resolved, do not guess or silently omit it; stop the work fail-safe.

## Guide

Read before inspecting/extracting JSON file values.

- Use tools that can interpret the structure of JSON, and do not determine values or hierarchies solely by text searches.
- In an environment where PowerShell can be used, give priority to `ConvertFrom-Json`, and if `jq` can be used on Unix systems, use `jq`. If you can use both, choose the one that suits your environment.
- As a general rule, grep, ripgrep, and Select-String are not used to extract JSON values, as they can cause missing items or false hits when searching across key names and structures.
- Use text search only when the purpose is clear, such as viewing the entire file as text or narrowing down the input for a structuring tool.
