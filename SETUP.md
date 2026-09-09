# セットアップ

`chezmoi`は設定ファイルの配置と、標準のパッケージ導入を行います。
通常の更新は、`chezmoi diff`で差分を確認してから`chezmoi apply`を実行し、必ず`chezmoi verify --exclude=scripts`で結果を検証します。意図しない差分、適用エラー、検証失敗、または検証後に残る差分があれば成功扱いにせず停止します。
設定ファイルの`sourceDir`は`~/.dotfiles`とし、WindowsとWSLでOS固有の絶対パスを共有しません。

WSL版Codex Remote Controlは任意機能です。
standalone版の導入、専用`CODEX_HOME`の作成、ログイン、Windowsの自動起動登録は、手動手順で行います。

## 共通

### 初回のみ: Aqua の導入

Windowsでは、まずAquaを導入し、PowerShellを再起動してから、リポジトリの定義に従ってCLIを揃えます。`aqua.yaml`には `chezmoi` も含まれています。

```powershell
winget install --id aquaproj.aqua --exact
aqua install --config "$HOME\.dotfiles\aqua.yaml"
```

`winget` が使えない場合は、[Aquaの公式リリース](https://github.com/aquaproj/aqua/releases)からWindows x64版を取得し、ユーザーの`PATH`にあるディレクトリへ配置してください。

~~~sh
# 初回はAqua管理のCLI（Codexを含む）を先に導入する
aqua install --config "$HOME/.dotfiles/aqua.yaml"
# リポジトリ以外のディレクトリで、プロジェクトや依頼を指定せずCodexを1回起動する
cd "$HOME"
codex
# 初回だけ、リポジトリを明示してchezmoiの設定を生成する
cd "$HOME/.dotfiles"
chezmoi --source "$HOME/.dotfiles" init
chezmoi diff
chezmoi apply
chezmoi verify --exclude=scripts
~~~

初回の`init`以後は、リポジトリのルートを明示せず`chezmoi diff`、`chezmoi apply`、`chezmoi verify --exclude=scripts`を実行できます。Windowsで初回の空起動を省略してグローバル状態がないまま適用すると、状態変更用テンプレートは失敗します。状態を自動作成・黙ってスキップはせず、空起動してから再試行してください。

`chezmoi apply`は、次の処理を実行します。

- `aqua install`：`aqua.yaml`に定義されたCLIを導入する。
- `uv python install`と`uv pip install`：Python 3.13とPyYAML 6.0.3を導入する。
- Windows：`winget import`で`winget.json`に定義されたAWS CLIとaws-vaultを導入する。
- `prek install`：Git hookを設定する。
- `.bashrc`、`.bashrc.interactive`、`.gitconfig`をホームディレクトリへ配置する。
- `.agents`と`.claude/skills`の共有リンクを作成する。

Gitの署名鍵は`chezmoi apply`で自動生成・登録しません。端末ごとに専用鍵を作成し、指紋と公開鍵を確認してからGitHubへ登録する必要があります。Shaulaの署名を有効にする場合は、初回適用後に[`README.manual.md`](README.manual.md)の「Gitコミット署名（Shaula）」を実行してください。

Linux、macOS、WSLでは、`aqua.yaml`に定義したCodex CLI（`openai/codex`）もAquaで導入されます。初回は上記の`aqua install`を`chezmoi apply`より先に実行します。
これは通常のCLIの導入であり、Remote Control用standalone版の導入やログインは行いません。

通常の`codex`は`CODEX_HOME`を設定せず、標準の`~/.codex`を仕事用アカウントとして使います。`~/.codex/config.toml`はリポジトリのポータブルなdefaultsを`modify_`方式でマージします。Codexが管理するプロジェクト履歴、hook状態、認証、ログ、セッションはリポジトリへ保存しません。
個人用は`pcodex`（`~/.codex-personal`）、WSL用CLIは`wcodex`（`~/.codex-wsl`）で起動します。`wcodex`は常に定義されますが、WSL用ホームが未セットアップなら実行時エラーになり、通常の`codex`へフォールバックしません。
個人用の`default_permissions`は通常`personal-standard`です。共有ワークスペースに加えてGitHub CLI設定の読み取りとGitHub APIへのネットワークアクセスを許可し、`D:\repository`と`C:\Users\<user>\work\gitmeta`への書き込みは`personal-emergency`へ分離しています。必要な場合だけ`pcodex -c 'default_permissions="personal-emergency"'`（または同等の明示指定）で緊急プロファイルを選択してください。絶対パスは`codex-personal-defaults.toml.local`にだけ置き、共有テンプレートには含めません。
端末固有の仕事用Codex設定は`codex-defaults.toml.local`、個人用設定は`codex-personal-defaults.toml.local`へ置きます。作成手順は[`README.manual.md`](README.manual.md)を参照してください。

### Codex CLIの更新

通常のCodex CLIはAquaで管理します。
更新するときは`aqua update codex`で`aqua.yaml`を更新し、差分を確認してコミットした後に`aqua install`を実行します。

Aqua管理の`codex`に対して`codex update`は使用しません。
`codex update`はstandalone版など導入方式を認識できる実体向けの更新経路であり、Aquaの宣言とGit管理を経由しないためです。

WSLでの具体的なコマンドは、[`codex-wsl/SETUP.md`](codex-wsl/SETUP.md)の「通常CLIを更新する」を参照してください。

## Windows

Windows x64ではAWS CLIとaws-vaultがAquaの対象外になるため、wingetで導入します。
Linux、macOSではwingetを実行せず、AWS系も含めてAquaで導入します。

WSL版Codex Remote Controlを使う場合は、[`codex-wsl/SETUP.md`](codex-wsl/SETUP.md)を上から順番に実行します。
`.codex-wsl`の詳細は、同文書から[`codex-wsl/CODEX_HOME.md`](codex-wsl/CODEX_HOME.md)へ進みます。

WSL側の`CODEX_HOME`は`$HOME/.codex-wsl`に分けます。
Windows側の`CODEX_HOME`と同じ物理ディレクトリを参照することは可能ですが、現在のWindows設定にはWSLで解釈できないパスが含まれています。
WSL固有の`AGENTS.md`を置き、Windows側の設定、ログ、セッション、SQLite状態を分離するため、現在は別ホームを使います。

以後、コミット時に`.pre-commit-config.yaml`のgitleaksフックが実行されます。

Agent Skillsの導入手順は、[`README.manual.md`](README.manual.md)の「Agent Skillsの導入」を参照してください。
Datadog MCPの設定手順は、同じ文書の「Datadog MCPの設定」を参照してください。
