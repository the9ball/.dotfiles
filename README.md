# .dotfiles

個人用の設定ファイルを管理するリポジトリです。`chezmoi`でホームディレクトリへ設定を配置し、`aqua`などで開発用CLIを揃えます。

## ライセンス

このリポジトリには、ファイルごとに出所・ライセンスが異なるものが含まれます。リポジトリ全体に一括適用するライセンスは設定していません。第三者由来または出所確認中のファイルは [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) に記録しています。公開・再配布時は各ファイルの条件と、サブモジュール内の `LICENSE` を確認してください。

## 共有と配布の範囲

このリポジトリは個人利用を前提としています。
内容を他者と共有することはありますが、リポジトリ全体や配下のファイルを第三者向けの配布物として提供することは想定していません。

将来、Skill、設定、スクリプトなどを配布する必要が生じた場合は、対象を個別のリポジトリへ切り出します。
ライセンス、依存関係、対応ホスト、バージョン管理、配布経路は、そのリポジトリで別途設計します。

このリポジトリでいう Skill の配置は、自分の Claude Code、Codex などの利用環境から設定や Skill を発見・参照できる状態を指し、第三者向けの配布を意味しません。

## 先に読むもの

- [`AGENTS.md`](AGENTS.md): このリポジトリで作業するときのルール
- [`SETUP.md`](SETUP.md): `chezmoi apply`で実行されるセットアップの概要
- [`README.manual.md`](README.manual.md): 新規環境を手動でセットアップする手順

## 新規環境の基本方針

`git`、`chezmoi`、`aqua`を先に用意し、リポジトリを配置してから次を実行します。AquaでCodex CLIを導入した後、リポジトリ以外のディレクトリで初回だけプロジェクトや依頼を指定せず`codex`を起動して終了し、Windowsで必要なグローバル状態を作成してから`chezmoi`を適用します。

```sh
aqua install --config "$HOME/.dotfiles/aqua.yaml"
cd "$HOME"
codex # プロジェクトや依頼を指定せず起動し、終了する
# 初回だけ、リポジトリの設定テンプレートからchezmoiの設定を生成する
cd "$HOME/.dotfiles"
chezmoi --source "$HOME/.dotfiles" init
chezmoi diff
chezmoi apply
chezmoi verify --exclude=scripts
```

`chezmoi`の設定は`sourceDir = "~/.dotfiles"`とし、WindowsとWSLで同じホーム相対のソースを解決します。初回の`init`以後は`chezmoi diff`、`chezmoi apply`、`chezmoi verify --exclude=scripts`を引数なしで実行できます。`chezmoi diff`に意図しない差分があれば適用せず停止し、適用後の`verify`が失敗した場合や差分が残る場合も成功扱いにせず原因を確認してください。既存環境で設定が古い場合も、リポジトリを明示した初回`init`を実行してから設定を更新してください。

OSごとの前提条件や初回のローカル設定は、[`README.manual.md`](README.manual.md)を参照してください。

Windowsの新規環境では、まずAquaを導入し、Aqua経由で`chezmoi`を含むCLIをセットアップします。

```powershell
winget install --id aquaproj.aqua --exact
aqua install --config "$HOME\.dotfiles\aqua.yaml"
```

`winget` が利用できない場合は、[Aquaの公式リリース](https://github.com/aquaproj/aqua/releases)からWindows x64版を取得し、ユーザーの`PATH`にあるディレクトリへ配置してください。

## AIに依頼するとき

最初にこのREADME、`README.manual.md`、`SETUP.md`、`AGENTS.md`を読ませ、OSと既存環境を確認させてください。たとえば次のように依頼できます。

> このリポジトリのREADME.md、README.manual.md、SETUP.md、AGENTS.mdを読んでください。現在のOSとインストール済みコマンドを確認し、新規環境のセットアップに必要な手順を提案してください。設定を変更する前に変更範囲を示し、`chezmoi diff`で差分を確認してから実行してください。認証情報や秘密情報はファイルに書き込まないでください。

設定変更やコミットまで依頼する場合は、対象ファイルと「コミットまで実行する」ことを明記してください。AIが作成した差分と、`chezmoi apply`がホームディレクトリへ行う変更を確認してから適用します。

## ローカル設定と秘密情報

`.bashrc.local.example`、`.gitconfig.local.example`、仕事用の`chezmoi/.chezmoitemplates/codex-defaults.toml.local.example`、個人用の`chezmoi/.chezmoitemplates/codex-personal-defaults.toml.local.example`を必要な環境へコピーして編集します。`*.local`はGitの追跡対象外ですが、認証情報や秘密情報をコミット・貼り付けしないでください。Codexの通常起動は仕事用の`codex`、個人用は`pcodex`、WSL用は`wcodex`です。個人用は通常`personal-standard`プロファイルを使い、GitHub CLI設定の読み取りとGitHub APIへのネットワークアクセスだけを許可します。`D:\repository`と`C:\Users\<user>\work\gitmeta`への書き込みは`personal-emergency`へ分離し、必要な作業でだけ`pcodex -c 'default_permissions="personal-emergency"'`（または同等の明示指定）で選択します。これらの絶対パスはホスト固有の`.local`オーバーレイに置きます。
