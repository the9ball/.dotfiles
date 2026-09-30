---
name: wsl-codex-exec
description: >
  Run the Aqua management Codex on the WSL side once non-interactively from the Windows version of Codex.
  It is used only when the user explicitly asks to run Codex on the WSL side, for example, `WSL側のCodexで実行して`; it is not started implicitly.
---

# One-time execution of WSL side Codex

This skill is used to pass a single request from the Windows version of Codex to the regular Codex CLI on the WSL side.
It will only be triggered if the user specifies `$wsl-codex-exec` or explicitly asks to run Codex on the WSL side, for example, `WSL側のCodexで実行して`.
This skill will not be implicitly activated from normal requests, verification, reviews, or script execution.

## Target

- Run Aqua management `codex exec` in WSL once.
- Return stdout, stderr, and exit code as is to the caller.
- Use the dedicated `CODEX_HOME` and the Aqua-managed CLI on the WSL side.

The following are not covered by this skill.

- Launching the interactive TUI. A person runs it directly in the WSL terminal.
- Launching `codex remote-control` (use the existing `codex-wsl/start-codex-wsl.sh` for that).
- `login`, `logout`, `update`, installation, plugin changes, settings changes.
- Starting additional Codex processes without the user's explicit consent.

## Prerequisite documents

The following documents are authoritative for the WSL regular CLI, the dedicated `CODEX_HOME`, the Aqua settings, and the distribution assumptions.

- repository-root relative `codex-wsl/SETUP.md`
- repository-root relative `codex-wsl/CODEX_HOME.md`

This Skill wrapper does not parse Markdown at runtime, but instead validates and uses the values defined in these documents.
When changing `CODEX_HOME`, the Aqua deployment, the repository location, or the target distribution, update the wrapper and the prerequisite documents at the same time.

## Fixed execution environment

A wrapper within WSL sets the following values:

- `AQUA_GLOBAL_CONFIG=$HOME/.dotfiles/aqua.yaml`
- `PATH=$HOME/.local/share/aquaproj-aqua/bin:$PATH`
- `CODEX_HOME=$HOME/.codex-wsl`
- Executable file `$HOME/.local/share/aquaproj-aqua/bin/codex`
- Working directory `$HOME/.dotfiles`

Do not pass the Windows-side `HOME`, `CODEX_HOME`, or authentication files as arguments.
Specify the WSL distribution `Ubuntu-20.04` explicitly, to match the current setup.
If the name does not exist, please stop without automatically selecting another distribution.

## Execution steps

1. Fix the user's explicit request as a single non-interactive task.
2. Don't embed the user body in Bash's `-c` and use the following fixed bridge:

~~~powershell
$fixedBashCommand = 'exec "$HOME/.dotfiles/link-targets/agents/skills/wsl-codex-exec/scripts/run-codex-exec.sh" "$@"'
& wsl.exe --distribution 'Ubuntu-20.04' --exec /bin/bash --noprofile --norc -c $fixedBashCommand wsl-codex-exec [codex-exec-options] -
~~~

3. The request body is passed from standard input, and `-` is used to specify the prompt for `codex exec`.
   Pass only user-specified options as separate arguments to `[codex-exec-options]`.
   We do not write the `exec` subcommand itself here because the wrapper adds `codex exec`.

example:

~~~powershell
$prompt = @'
In the Codex on the WSL side, inspect the current working tree read-only and report only the results.
'@
$prompt | & wsl.exe --distribution 'Ubuntu-20.04' --exec /bin/bash --noprofile --norc -c $fixedBashCommand wsl-codex-exec --sandbox read-only -
~~~

Arguments are always treated as `"$@"` on the Bash side. Do not use `$*`, `eval`, string concatenated commands, or `bash -c` / `bash -lc` with user body.

## Safety and failure handling

- The wrapper exits with a non-zero status if the Aqua configuration, the dedicated `CODEX_HOME`, the working directory, or the Aqua-managed Codex executable does not exist.
- The wrapper does not install, log in, create directories, or background.
- Do not automatically add privilege relaxation options such as `--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust`, `--approve-for-me`.
- Returns the Codex standard output/standard error and exit code without processing. Does not automatically re-execute the same request when it fails.
- Do not save credentials, tokens, or the contents of `CODEX_HOME` in the repository.
- WSL startup, Codex CLI execution, and exit code confirmation are treated as a single synchronous process, and no processes are left behind.
