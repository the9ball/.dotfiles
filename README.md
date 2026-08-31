# .dotfiles

個人用の設定ファイルを管理するリポジトリです。`chezmoi`でホームディレクトリへ設定を配置し、`aqua`などで開発用CLIを揃えます。

## ライセンス

このリポジトリには、ファイルごとに出所・ライセンスが異なるものが含まれます。リポジトリ全体に一括適用するライセンスは設定していません。第三者由来または出所確認中のファイルは [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) に記録しています。公開・再配布時は各ファイルの条件と、サブモジュール内の `LICENSE` を確認してください。

## 先に読むもの

- [`AGENTS.md`](AGENTS.md): このリポジトリで作業するときのルール
- [`SETUP.md`](SETUP.md): `chezmoi apply`で実行されるセットアップの概要
- [`README.manual.md`](README.manual.md): 新規環境を手動でセットアップする手順

## 新規環境の基本方針

`git`、`chezmoi`、`aqua`を先に用意し、リポジトリを配置してから次を実行します。

```sh
chezmoi --source "$HOME/.dotfiles" diff
chezmoi --source "$HOME/.dotfiles" apply
```

OSごとの前提条件や初回のローカル設定は、[`README.manual.md`](README.manual.md)を参照してください。

## AIに依頼するとき

最初にこのREADME、`README.manual.md`、`SETUP.md`、`AGENTS.md`を読ませ、OSと既存環境を確認させてください。たとえば次のように依頼できます。

> このリポジトリのREADME.md、README.manual.md、SETUP.md、AGENTS.mdを読んでください。現在のOSとインストール済みコマンドを確認し、新規環境のセットアップに必要な手順を提案してください。設定を変更する前に変更範囲を示し、`chezmoi diff`で差分を確認してから実行してください。認証情報や秘密情報はファイルに書き込まないでください。

設定変更やコミットまで依頼する場合は、対象ファイルと「コミットまで実行する」ことを明記してください。AIが作成した差分と、`chezmoi apply`がホームディレクトリへ行う変更を確認してから適用します。

## ローカル設定と秘密情報

`.bashrc.local.example`と`.gitconfig.local.example`を各環境用にコピーして編集します。`*.local`はGitの追跡対象外ですが、認証情報や秘密情報をコミット・貼り付けしないでください。
