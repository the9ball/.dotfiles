---
name: code-formatting
description: Before creating or editing program source code, resolve the applicable EditorConfig settings and select formatting tools; after editing, format and verify the changed files. Also use for explicit code-formatting requests. Does not trigger for prose-only edits or read-only code review.
---

# Code formatting

Apply this skill before the first source-code write, including scripts and new files. Carry its selected settings and validation route through the edit and its final verification. The trigger phrase "プログラムコードの編集前" means "before editing program source code."

## Before editing

1. Identify the files to create or edit, their absolute paths, and the relevant project. For a new file, use its intended destination even when the file or its parent directory does not exist yet.
2. Prefer the project's established formatter and lint commands when they support the relevant language and settings. Check existing configuration and tool availability before selecting a command. Read [references/csharp.md](references/csharp.md) only for C#.
3. For the default route, resolve effective settings with the EditorConfig Core CLI, for example `editorconfig ABSOLUTE_FILE_PATH`. Pass multiple paths in one invocation when useful. A compatible EditorConfig Core library is an acceptable equivalent. A native tool that reads the applicable EditorConfig files may handle resolution itself; obtain a Core summary only when useful for editing or missing coverage. Keep resolved properties in context; read configuration source only to investigate unsupported settings, conflicts, or unexpected results.
4. Reuse a resolution while the target path and governing configuration stay unchanged. Re-resolve for new destinations, moves, or configuration changes.

EditorConfig searches from each target's directory upward until `root = true` in the preamble or the filesystem root. Do not stop at a Git root. Matching sections merge by property: nearer configuration overrides ancestors, later matching sections override earlier ones, and `unset` removes a property. Delegate glob matching and resolution to a Core implementation rather than implementing an approximate parser or scanning the entire repository.

Honor indentation, newline convention, encoding/BOM, trailing whitespace, and final-newline settings where specified. For unspecified or unset properties, follow project conventions and surrounding code. Language-specific properties require a tool that understands them; resolving a property does not mean a tool can enforce it.

## Tool routing

- **Default:** Use Core to resolve settings before editing, then editorconfig-checker to verify the changed text files. It is a validator for supported text-formatting properties, not a language-aware formatter.
- **Language-specific route:** Delegate formatting and applicable style validation to the project's native tool when available. Core output remains useful as a small settings summary; do not require a duplicate checker run for properties already covered by the native tool. Use checker for applicable text properties the native tool does not cover.
- **Other languages:** Confirm which EditorConfig properties the chosen formatter actually honors. A formatter's own configuration may take precedence or support only a subset. Do not silently choose precedence when project rules conflict; resolve the conflict from the project's documented policy or report the ambiguity.
- **Tool discovery:** Prefer pinned project tools and the existing package manager. Aqua's standard registry provides `editorconfig/editorconfig-core-go` from v4.572.0 onward; it exposes `editorconfig` and resolves effective properties, including language-specific properties that it does not enforce. Use `editorconfig-checker/editorconfig-checker` for validation; v4 exposes `editorconfig-checker`, while older versions expose `ec`. Check the installed version's help. Both packages support Linux, macOS, and Windows; consult their version-specific platform coverage when using older releases.
- **Missing tools:** Report the unavailable capability and use an available compatible Core or native tool where it covers the requirement. If the required resolution or validation remains unavailable, mark it unverified. Do not silently install tools or substitute checker success for unsupported checks; propose provisioning through the user's existing dependency management when necessary.

## After editing

1. Format only the files in the authorized change scope, using the selected tool. Preserve existing user changes and inspect the resulting diff. Avoid unrelated whole-file rewrites; if enforcing a file-level property requires changing existing content outside the authorized scope, resolve that boundary before applying it.
2. For the default route, pass an explicit list of changed files to checker, including new untracked files. For example, use `editorconfig-checker FILE_PATH...`, or the verified older executable name. Do not rely on its default Git file discovery. Confirm exclusions or dry-run output when there is a risk that a target was skipped.
3. Use the native tool's verification mode for language-specific checks. Treat parser, project-load, and tool-execution failures separately from formatting violations. An empty diagnostic list from a failed or skipped check is not success.
4. Fix violations attributable to the task and rerun the affected checks. If a failure persists after two evidence-based corrections, identify the remaining cause and report it instead of looping. Existing out-of-scope violations are reported separately and are not automatically added to the task.

Checker supports only its documented property set; for example, `tab_width` is not supported by the currently documented release. Its automatic fixes cover only some properties and can rewrite files. Use such fixes only within the same approved scope; indentation, encoding, and language syntax need the appropriate editing or formatting route.

Do not modify `.editorconfig`, formatter settings, severity settings, or exclusions merely to make verification pass. Configuration changes require their own task scope.

## Context and reporting

- Keep configuration loading narrow: effective properties for targets, relevant native-tool options, and actionable diagnostics. Batch paths and summarize repeated warnings without hiding locations or causes needed to fix them.
- Report the tools used, checked scope, and result briefly. Identify unsupported rules, skipped files, missing tools, and pre-existing violations when they limit the result. Claim compliance only for checks that actually ran and covered the targets.

## Sources

- [EditorConfig resolution specification](https://spec.editorconfig.org/#file-processing)
- [EditorConfig Core CLI](https://docs.editorconfig.org/en/master/editorconfig.html)
- [EditorConfig Core Go](https://github.com/editorconfig/editorconfig-core-go)
- [editorconfig-checker support and usage](https://github.com/editorconfig-checker/editorconfig-checker)
