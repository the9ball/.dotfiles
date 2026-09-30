# link-targets

Place repository-specific shared settings in this directory.
On the host side, it is referenced from each publication destination via symlink/junction.

```text
link-targets/
├── agents/
│   ├── AGENTS.md     # ~/.agents/AGENTS.md
│   ├── guides/
│   ├── hooks/        # shared in ~/.agents/hooks
│   ├── reference-map.json
│   ├── skills/       # shared between ~/.agents/skills and ~/.claude/skills
│   └── tools/
└── claude/
    └── agents/       # ~/.claude/agents
```

## Original copy and publication location

`link-targets/agents/` is the original version of `~/.agents/`.
`link-targets/agents/hooks/` is the original Codex hook shared from `~/.agents/hooks/`.
`link-targets/agents/skills/` is shared from `~/.agents/skills/` and `~/.claude/skills/`.
`link-targets/claude/agents/` is the original version of `~/.claude/agents/`.

The publication destination is a link to refer to the original content.
Do not edit the publishing destination path directly, but edit the original side.

Place repository-specific instructions such as placement, publishing location, and migration steps in this README, and keep only always-needed work rules in the shared `AGENTS.md`.

Any subsequent modifications will be made only under this directory. The old `.agents/` and `.claude/agents/` have been deleted as the migration has been completed.

## Language

Write agent-facing documentation in English, including `AGENTS.md`, skills, and guides. Keep Japanese trigger phrases, exact output strings, status values, and terms of art (for example, `保守して`) literal in Japanese and add an English gloss.

## Precautions during migration

chezmoi's junction/symlink management script stops without automatically repairing target mismatches on existing links.
Therefore, after updating the management script, first re-establish the runtime link / junction for each OS and then execute `chezmoi apply`.
Even if the old target directory has already been deleted, accept it for migration when the link still points to the old canonical path.
Only files tracked by Git are copied during migration. Local settings and third-party skills in the old tree will not be included in the migration, and will be restored in the installation steps for each skill if necessary.

### POSIX (Linux / macOS / WSL)

Replace `repository_root` with the absolute path to this repository. Before deleting anything, verify that every existing path is a symlink; if any path is a regular file or directory, stop without deleting it.

```sh
set -eu
repository_root=/path/to/.dotfiles
canonical_directory() {
    (cd "$1" && pwd -P)
}
link_target() {
    if target_path=$(canonical_directory "$1" 2>/dev/null); then
        printf '%s\n' "$target_path"
        return
    fi
    target_path=$(readlink "$1")
    case "$target_path" in
        /*) printf '%s\n' "$target_path" ;;
        *) printf '%s/%s\n' "$(dirname "$1")" "$target_path" ;;
    esac
}
ensure_migratable_link() {
    link_path=$1
    legacy_target_path=$2
    target_path=$3
    test -d "$target_path" || { printf 'target does not exist: %s\n' "$target_path" >&2; exit 1; }
    test -L "$link_path" || { printf 'not a symlink: %s\n' "$link_path" >&2; exit 1; }
    actual_target_path=$(link_target "$link_path")
    target_path=$(canonical_directory "$target_path")
    if test "$actual_target_path" = "$target_path"; then
        return
    fi
    if test -d "$legacy_target_path" && test "$actual_target_path" = "$(canonical_directory "$legacy_target_path")"; then
        return
    fi
    if test "$actual_target_path" = "$legacy_target_path"; then
        return
    fi
    printf 'symlink target mismatch: %s (expected legacy or new target)\n' "$link_path" >&2
    exit 1
}
ensure_migratable_link "$HOME/.agents" "$repository_root/.agents" "$repository_root/link-targets/agents"
ensure_migratable_link "$HOME/.claude/skills" "$repository_root/.agents/skills" "$repository_root/link-targets/agents/skills"
ensure_migratable_link "$HOME/.claude/agents" "$repository_root/.claude/agents" "$repository_root/link-targets/claude/agents"
for link_path in "$HOME/.agents" "$HOME/.claude/skills" "$HOME/.claude/agents"; do
    rm "$link_path"
done
mkdir -p "$HOME/.claude"
ln -s "$repository_root/link-targets/agents" "$HOME/.agents"
ln -s "$repository_root/link-targets/agents/skills" "$HOME/.claude/skills"
ln -s "$repository_root/link-targets/claude/agents" "$HOME/.claude/agents"
```

### Windows PowerShell

Replace `$repositoryRoot` with the absolute path to this repository. If an existing item's `LinkType` is not `Junction`, stop without deleting it.

```powershell
$repositoryRoot = 'C:\path\to\.dotfiles'
$links = @(
    @{ Path = Join-Path $env:USERPROFILE '.agents'; LegacyTarget = Join-Path $repositoryRoot '.agents'; Target = Join-Path $repositoryRoot 'link-targets\agents' },
    @{ Path = Join-Path $env:USERPROFILE '.claude\skills'; LegacyTarget = Join-Path $repositoryRoot '.agents\skills'; Target = Join-Path $repositoryRoot 'link-targets\agents\skills' },
    @{ Path = Join-Path $env:USERPROFILE '.claude\agents'; LegacyTarget = Join-Path $repositoryRoot '.claude\agents'; Target = Join-Path $repositoryRoot 'link-targets\claude\agents' }
)
foreach ($link in $links) {
    if (-not (Test-Path -LiteralPath $link.Target -PathType Container)) { throw "target does not exist: $($link.Target)" }
    $existing = Get-Item -LiteralPath $link.Path -Force -ErrorAction Stop
    if ($existing.LinkType -ne 'Junction') { throw "not a junction: $($link.Path)" }
    $actualTarget = [IO.Path]::GetFullPath([string]$existing.Target)
    $expectedTarget = [IO.Path]::GetFullPath($link.Target)
    if ($actualTarget.Equals($expectedTarget, [StringComparison]::OrdinalIgnoreCase)) {
        continue
    }
    $legacyTarget = [IO.Path]::GetFullPath($link.LegacyTarget)
    if (-not $actualTarget.Equals($legacyTarget, [StringComparison]::OrdinalIgnoreCase)) {
        throw "junction target mismatch: $($link.Path) -> $actualTarget (expected legacy or new target)"
    }
}
foreach ($link in $links) {
    Remove-Item -LiteralPath $link.Path
}
foreach ($link in $links) {
    New-Item -ItemType Junction -Path $link.Path -Target $link.Target | Out-Null
}
```

After re-linking, execute `chezmoi diff`, `chezmoi apply`, and `chezmoi verify --exclude=scripts`.
