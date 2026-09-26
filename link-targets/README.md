# link-targets

このディレクトリには、リポジトリ固有の共有設定を置きます。
ホスト側では、symlink / junction を通じて各公開先から参照します。

```text
link-targets/
├── agents/
│   ├── AGENTS.md     # ~/.agents/AGENTS.md
│   ├── guides/
│   ├── hooks/        # ~/.agents/hooks で共有
│   ├── reference-map.json
│   ├── skills/       # ~/.agents/skills と ~/.claude/skills で共有
│   └── tools/
└── claude/
    └── agents/       # ~/.claude/agents
```

## 正本と公開先

`link-targets/agents/` が `~/.agents/` の正本です。
`link-targets/agents/hooks/` は `~/.agents/hooks/` から共有する Codex hook の正本です。
`link-targets/agents/skills/` は `~/.agents/skills/` と `~/.claude/skills/` から共有します。
`link-targets/claude/agents/` が `~/.claude/agents/` の正本です。

公開先は正本の内容を参照するためのリンクです。
公開先のパスを直接編集せず、正本側を編集します。

配置、公開先、移行手順などのリポジトリ固有の説明はこの README に置き、共有 `AGENTS.md` には常時必要な作業ルールだけを置きます。

以後の修正はこのディレクトリ配下だけに行います。旧 `.agents/` および `.claude/agents/` は移行完了に伴い削除済みです。

## 移行時の注意

chezmoi の junction / symlink 管理スクリプトは、既存リンクの target mismatch を自動修復せず停止します。
そのため、管理スクリプトを更新した後は、各 OS の runtime link / junction を先に張り直してから `chezmoi apply` を実行してください。
旧 target のディレクトリが既に削除されていても、リンクが旧正本のパスを指していれば移行対象として受け入れます。
移行時にコピーするのは Git で追跡しているファイルだけです。旧ツリーにあるローカル設定や第三者スキルは移行対象に含めず、必要なら各スキルの導入手順で復元します。

### POSIX（Linux / macOS / WSL）

`repository_root` はこのリポジトリの絶対パスに置き換えてください。削除前にすべての既存パスが symlink であることを確認し、通常のファイルやディレクトリなら停止します。

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

`$repositoryRoot` をこのリポジトリの絶対パスに置き換えてください。既存項目の `LinkType` が `Junction` でない場合は削除せず停止します。

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

張り直し後に `chezmoi diff`、`chezmoi apply`、`chezmoi verify --exclude=scripts` を実行してください。
