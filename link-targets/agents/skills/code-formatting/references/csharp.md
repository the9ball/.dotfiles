# C# formatting and validation

Use the repository's established C# formatter and analyzer commands. For ordinary SDK projects, `dotnet format` is the default native route. The generic checker does not enforce C# properties such as brace placement, `var` preferences, expression-bodied members, or naming rules.

## Select the scope

- Identify the owning project or solution explicitly. Pass changed files with `--include` using paths relative to the command's working directory. Files must belong to the selected workspace; a skipped or unloaded file has not been validated.
- Respect the project's SDK selection and installed command's help. Use `--no-restore` when dependencies are already restored. Loading errors require resolving the project/dependency issue; do not hide them with exclusions.
- For standalone C# files without a loadable project, `dotnet format whitespace --folder DIRECTORY` can handle formatting. This does not establish semantic style or analyzer coverage; report that limitation.

## Format and verify

- `dotnet format whitespace` handles C# whitespace-formatting settings, including syntax-aware indentation, spacing, and line breaks.
- `dotnet format style` handles supported code-style fixes. Select `--severity info` when informational preferences should be included; the default threshold is `warn`, and disabled diagnostics remain disabled.
- `dotnet format analyzers` handles available analyzer fixes outside the code-style category. Run it only when those fixes belong to the task; do not automatically apply semantic changes for a formatting-only request.
- Add `--verify-no-changes` to check whether the selected command would change source files. Combine it with the same project and `--include` scope used for formatting. Verification can still produce project build/restore artifacts; it is not a promise of no filesystem writes.
- No-change verification covers available fixes, not every diagnostic. Naming rules, quality rules, or third-party analyzers without code fixes require the project's analyzer/build validation where applicable. Do not claim full C# policy compliance from `dotnet format` alone. Follow applicable build/test instructions if those commands are needed.
- Use editorconfig-checker only for applicable common text properties not covered by the native route, such as an encoding/BOM requirement the selected tool does not validate. Account for the installed checker's supported properties.

Do not introduce an SDK, project file, analyzer package, or Unity project change merely to make a file formatable. When the native route is unavailable, use the project's supported alternative and report the missing coverage.

## Sources

- [dotnet format options and subcommands](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-format)
- [.NET code style rule options](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/code-style-rule-options)
