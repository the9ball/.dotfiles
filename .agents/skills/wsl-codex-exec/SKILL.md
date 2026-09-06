---
name: wsl-codex-exec
description: >
  Windows版CodexからWSL側のAqua管理Codexを非対話で一回実行する。
  ユーザーが明示的にWSL側Codexの実行を指示した場合だけ使用し、暗黙には起動しない。
---

# WSL側 Codex の一回実行

このSkillは、Windows版CodexからWSL側の通常Codex CLIへ一回分の依頼を渡すために使用します。
ユーザーが `$wsl-codex-exec`、または「WSL側のCodexで実行して」のように明示した場合だけ発動します。
通常の依頼、検証、レビュー、スクリプト実行から暗黙にこのSkillを起動しません。

## 対象

- WSL内のAqua管理 `codex exec` を一回実行する。
- stdout、stderr、終了コードを呼び出し元へそのまま返す。
- WSL側の専用 `CODEX_HOME` とAqua管理CLIを使用する。

次はこのSkillの対象外です。

- 対話型TUIの起動。人がWSLのターミナルで直接実行する。
- `codex remote-control` の起動。既存の `codex-wsl/start-codex-wsl.sh` を使用する。
- `login`、`logout`、`update`、インストール、プラグイン変更、設定変更。
- ユーザーの明示なしに、別のCodexプロセスを追加で起動すること。

## 前提文書

WSLの通常CLI、専用 `CODEX_HOME`、Aqua設定、ディストリビューションの前提は、次の文書を正とします。

- [`codex-wsl/SETUP.md`](../../../codex-wsl/SETUP.md)
- [`codex-wsl/CODEX_HOME.md`](../../../codex-wsl/CODEX_HOME.md)

このSkillのラッパーは実行時にMarkdownを解析せず、これらの文書で定めた値を検証して使用します。
`CODEX_HOME`、Aquaの配置、リポジトリの場所、または対象ディストリビューションを変更するときは、ラッパーと前提文書を同時に更新してください。

## 固定する実行環境

WSL内のラッパーが次の値を設定します。

- `AQUA_GLOBAL_CONFIG=$HOME/.dotfiles/aqua.yaml`
- `PATH=$HOME/.local/share/aquaproj-aqua/bin:$PATH`
- `CODEX_HOME=$HOME/.codex-wsl`
- 実行ファイル `$HOME/.local/share/aquaproj-aqua/bin/codex`
- 作業ディレクトリ `$HOME/.dotfiles`

Windows側の `HOME`、`CODEX_HOME`、認証ファイルを引数として渡しません。
WSLディストリビューションは現在のセットアップに合わせて `Ubuntu-20.04` を明示します。
名前が存在しない場合は自動で別のディストリビューションを選ばず停止してください。

## 実行手順

1. ユーザーの明示的な依頼内容を一回の非対話タスクとして確定します。
2. Bashの `-c` にユーザー本文を埋め込まず、次の固定ブリッジを使用します。

~~~powershell
$fixedBashCommand = 'exec "$HOME/.dotfiles/.agents/skills/wsl-codex-exec/scripts/run-codex-exec.sh" "$@"'
& wsl.exe --distribution 'Ubuntu-20.04' --exec /bin/bash --noprofile --norc -c $fixedBashCommand wsl-codex-exec [codex-exec-options] -
~~~

3. 依頼本文は標準入力から渡し、`-` を `codex exec` のプロンプト指定に使います。
   `[codex-exec-options]` には、ユーザーが明示したオプションだけを個別の引数として渡します。
   ラッパーが `codex exec` を追加するため、ここに `exec` サブコマンド自体は書きません。

例:

~~~powershell
$prompt = @'
WSL側のCodexで、現在の作業ツリーを読み取り専用で調査し、結果だけ報告してください。
'@
$prompt | & wsl.exe --distribution 'Ubuntu-20.04' --exec /bin/bash --noprofile --norc -c $fixedBashCommand wsl-codex-exec --sandbox read-only -
~~~

引数はBash側で常に `"$@"` として扱います。`$*`、`eval`、文字列連結したコマンド、ユーザー本文を含む `bash -c` / `bash -lc` は使用しません。

## 安全と失敗時の扱い

- ラッパーはAqua設定、専用 `CODEX_HOME`、作業ディレクトリ、Aqua管理のCodex実体が存在しない場合に非0で停止します。
- ラッパーはインストール、ログイン、ディレクトリ作成、バックグラウンド化を行いません。
- `--dangerously-bypass-approvals-and-sandbox`、`--dangerously-bypass-hook-trust`、`--approve-for-me` などの権限緩和オプションを自動追加しません。
- Codexの標準出力・標準エラーと終了コードを加工せず返します。失敗時に同じ依頼を自動再実行しません。
- 認証情報、トークン、`CODEX_HOME` の実体をリポジトリへ保存しません。
- WSL起動、Codex CLI実行、終了コードの確認までを一回の同期処理として扱い、プロセスを残しません。
