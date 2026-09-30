---
name: dd-readonly-delegate
description: Used for reference requests regarding Datadog metrics, logs, dashboards, monitoring, Datadog MCP, dd-logs, and dd-docs. Delegate read-only investigations to subagents, but keep knowledge and MCP context on the main thread for ongoing Datadog investigations.
metadata:
  short-description: Delegate Datadog read-only investigations safely
---

# Datadog Read-only Delegation

This is a routing skill for carrying out Datadog reference work safely, after checking the necessary skills and how to use the MCP.

## Routing

First, determine whether the request is a one-off or an ongoing investigation.

- As a general rule, one-off metrics, logs, dashboards, and document references should be delegated to read-only subagents.
- If you need to adjust a query multiple times based on recent results, explore across multiple pieces of Datadog data, or expect constant references during a conversation, load the related skills and how to use the MCP on the main thread and run the work there directly. This avoids the loss of context and the back-and-forth that delegation causes.
- If there is an existing agent or session that is already responsible for reading and investigating the same purpose, target, and authority range, and it can be reused, reuse it instead of creating a new one. Whether one can be reused depends on the execution environment, so if there is no way to reuse one, you may delegate to a new one.
- If the subagent asks for necessary permissions, authentication, user approval, or write operations, it stops and returns to the main thread.

## Skill and tool selection

- If you need attention on log search, aggregation, and costs, read `dd-logs`.
- Read `dd-docs` to check Datadog's features, limitations, and permission specifications.
- `dd-pup` is a procedure for Pup CLI and is managed separately from MCP authentication settings. When using SAT with Pup, settings such as `DD_ACCESS_TOKEN` are required on the Pup side as well. For reading through MCP, prefer the read tools of the connected Datadog MCP.
- When using a Datadog MCP connected with SAT, choose from the available MCP reading tools.
- If the tool's inputs and outputs cannot be determined from the skill description alone, check the available tool definitions and actual responses before calling.

## Authorization and privacy

- This skill is read-only. Do not modify Datadog settings, permissions, authentication, monitors, dashboards, workflows, etc.
- Never display or request a SAT value, save it to a file, or embed it in a delegation prompt. This applies wherever it is stored: treat it the same whether it is in an environment variable (such as `DD_ACCESS_TOKEN`), in the `Authorization` header of an MCP configuration file, or in any other configuration file.
- Specify the minimum necessary time range, granularity, and result-count limit for each query. Do not return or repeat log text, host names, email addresses, user IDs, etc. unless needed for the answer.
- If an external write or destructive operation is required, do not continue the read-only investigation; ask for the user's explicit approval.

## Delegation prompt

When delegating to a subagent, do not assume it can read the parent thread; state the following explicitly:

- Investigation target, query, period, granularity, upper limit on number of cases
- Read the required skills (`dd-logs`, `dd-docs`, etc.) first
- Do not handle SAT values, and use the available Datadog MCP read tools
- Do not write, change permissions, change authentication, or create additional tasks.
- Return the executed query, target period, summary of results, number/unit, errors, and unconfirmed items.
- Keep raw logs and confidential information to a minimum necessary, and use aggregated information if possible.

## Main-thread verification

Do not treat the subagent's report alone as completion. In the main thread, check that the results correspond to the request, and check the period, units, queries, and any permission errors. Separate facts, inferences, and unconfirmed items in the final answer.
