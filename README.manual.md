# 手動セットアップ

新規環境でこのリポジトリを使い始めるときの手順です。通常の更新は、リポジトリのルートで`chezmoi --source "$HOME/.dotfiles" apply`を実行します。

## 1. 前提コマンドを用意する

次のコマンドを、使用するOSの方法でインストールします。

- Git
- chezmoi
- aqua
- Windows: `winget`

## 2. リポジトリを配置する

```sh
git clone https://github.com/the9ball/.dotfiles.git "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
git submodule update --init --recursive
```

すでにclone済みの場合は、`git pull --rebase`と`git submodule update --init --recursive`で更新します。

## 3. マシン固有の設定を作る

POSIX系のシェルでは次を実行します。

```sh
cp .bashrc.local.example "$HOME/.bashrc.local"
cp .gitconfig.local.example "$HOME/.gitconfig.local"
```

WindowsのPowerShellでは`cp`の代わりに次を実行します。

```powershell
Copy-Item .bashrc.local.example "$HOME/.bashrc.local"
Copy-Item .gitconfig.local.example "$HOME/.gitconfig.local"
```

コピーしたファイルに名前、メールアドレス、マシン固有のPATHなどを設定します。認証情報は保存せず、必要なツールの認証機能を使ってください。

## 4. 差分を確認して適用する

まず適用前の差分を確認し、問題がなければ適用します。

```sh
chezmoi --source "$HOME/.dotfiles" diff
chezmoi --source "$HOME/.dotfiles" apply
chezmoi --source "$HOME/.dotfiles" verify
```

`apply`では、設定ファイルの配置に加えて次の処理が実行されます。

- `aqua.yaml`に定義されたCLIのインストール
- Windowsでは`winget.json`に定義されたAWS CLIとaws-vaultのインストール
- `prek`のGit hook設定
- `~/.agents`、`~/.claude/skills`、`~/.claude/agents`の共有リンク作成（Windowsではジャンクション）

これらのパスに通常のディレクトリや別のリンクがすでにある場合、スクリプトは上書きせず停止します。既存の内容とリンク先を確認し、必要なら手動で退避してから再実行してください。

## 5. 適用後の確認

シェルを再起動するか設定を読み込み直し、Gitや必要なCLIが使えることを確認します。設定を更新したときは、次の順に実行します。

```sh
cd "$HOME/.dotfiles"
git pull --rebase
git submodule update --init --recursive
chezmoi --source "$HOME/.dotfiles" apply
```

セットアップの詳細な挙動を確認したい場合は、[`SETUP.md`](SETUP.md)と`chezmoi/.chezmoiscripts/`を参照してください。
