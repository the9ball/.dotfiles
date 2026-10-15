# セットアップ

`chezmoi`は設定ファイルの配置と、標準のパッケージ導入を行います。
通常の更新は、`chezmoi diff`で差分を確認してから`chezmoi apply`を実行し、必ず`chezmoi verify --exclude=scripts`で結果を検証します。意図しない差分、適用エラー、検証失敗、または検証後に残る差分があれば成功扱いにせず停止します。
設定ファイルの`sourceDir`は`~/.dotfiles`とし、WindowsとWSLでOS固有の絶対パスを共有しません。

WSL版Codex Remote Controlは任意機能です。
standalone版の導入、ログイン、Windowsの自動起動登録は手動手順で行います。`chezmoi apply`は共通hook登録用に`.codex-wsl/hooks.json`を配置し、必要なら`.codex-wsl`ディレクトリを作成しますが、standalone実体や認証情報は作成しません。

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

- 設定ファイルの変更前に`aqua-policy.yaml`のSHA-256を検証し、固定した確認済みの値と一致する場合だけ`aqua policy allow`を実行する。
- `aqua install`：`aqua.yaml`に定義されたCLIを導入する。
- `uv python install`と`uv pip install`：Python 3.13とPyYAML 6.0.3を導入する。
- Windows：`winget import`で`winget.json`に定義されたAWS CLIとaws-vaultを導入する。
- `prek install`：Git hookを設定する。
- `.bashrc`、`.bashrc.interactive`、`.gitconfig`をホームディレクトリへ配置する。
- `link-targets/agents`、`link-targets/agents/skills`、`link-targets/claude/agents`を、それぞれ`~/.agents`、`~/.claude/skills`、`~/.claude/agents`へ共有リンクとして公開する。

ポリシーのハッシュ不一致、ファイル欠落、検証コマンドの失敗、承認失敗があれば、設定ファイルの変更前に適用を停止します。
ポリシーを変更するときは、`aqua-policy.yaml`と`aqua-registry.yaml`の内容を確認し、`chezmoi/.chezmoiscripts/run_before_00-aqua-policy.ps1.tmpl`と`run_before_00-aqua-policy.sh.tmpl`の固定ハッシュを更新します。
`run_before`内の名前順でガードを先頭にするため、`00-`をガード用に予約し、ほかの`run_before`には後続の名前を付けます。
ポリシーからハッシュを自動生成するテンプレートにはしません。
この検証は信頼したリポジトリのスクリプトを実行する前提で、ポリシーの変更を検出します。
ローカルレジストリの定義を変更するときも、配布元と実行内容を別途確認してください。

初回の`aqua install`など、chezmoiを経由しない導入では、この自動承認は実行されません。
ローカルレジストリが未承認なら、[Windows SSHの手順](README.manual.md#windows-ssh-の既定シェルと-psmux)に従い、内容を確認して手動で信頼登録してから再実行します。

既存環境から移行する場合は、`chezmoi apply`の前に[`link-targets/README.md`](link-targets/README.md)の手順でruntime link / junctionを張り直してください。管理スクリプトはtarget mismatchを自動修復しません。

Gitの署名鍵は`chezmoi apply`で自動生成・登録しません。端末ごとに専用鍵を作成し、指紋と公開鍵を確認してからGitHubへ登録する必要があります。Shaulaの署名を有効にする場合は、初回適用後に[`README.manual.md`](README.manual.md)の「Gitコミット署名（Shaula）」を実行してください。

Linux、macOS、WSLでは、`aqua.yaml`に定義したCodex CLI（`openai/codex`）もAquaで導入されます。初回は上記の`aqua install`を`chezmoi apply`より先に実行します。
これは通常のCLIの導入であり、Remote Control用standalone版の導入やログインは行いません。

通常の`codex`は`CODEX_HOME`を設定せず、標準の`~/.codex`を仕事用アカウントとして使います。`~/.codex/config.toml`はリポジトリのポータブルなdefaultsを`modify_`方式でマージします。Codexが管理するプロジェクト履歴、hook状態、認証、ログ、セッションはリポジトリへ保存しません。
個人用は`pcodex`（`~/.codex-personal`）、WSL用CLIは`wcodex`（`~/.codex-wsl`）で起動します。`wcodex`は常に定義されますが、WSL用ホームが未セットアップなら実行時エラーになり、通常の`codex`へフォールバックしません。
個人用の`default_permissions`は通常`personal-standard`です。共有ワークスペースに加えてGitHub CLI設定の読み取りとGitHub APIへのネットワークアクセスを許可し、追加の書き込み許可は`personal-emergency`へ分離しています。必要な場合だけ`pcodex -c 'default_permissions="personal-emergency"'`（または同等の明示指定）で緊急プロファイルを選択してください。filesystem permission のパスは許可範囲であり、通常のcheckoutや作業場所の指定ではありません。絶対パスは`codex-personal-defaults.toml.local`にだけ置き、共有テンプレートには含めません。
端末固有の仕事用Codex設定は`codex-defaults.toml.local`、個人用設定は`codex-personal-defaults.toml.local`へ置きます。作成手順は[`README.manual.md`](README.manual.md)を参照してください。

GitHub CLI の認証状態確認用 hook は、共通スクリプトを`~/.agents/hooks/`に置き、chezmoiで各`CODEX_HOME`の`hooks.json`へ登録します。共通設定で使うPython 3.13は`chezmoi apply`が`uv`経由で導入し、hookもその管理下のPythonから起動します。初回やhook定義を変更した後は、そのホームでCodexを再起動し、`/hooks`から定義を確認して信頼してください。信頼状態はホームごとに必要です。詳細は[Codex Hooks](https://learn.chatgpt.com/docs/hooks)を参照してください。

hookが調べるのは、CodexのBashツールに渡されたコマンド中の直接的な`gh auth status` / `gh.exe auth status`呼び出しです。一般的な`;`、`&&`、`||`や単純な`if`の区切りは認識し、固定delimiterのhere-document本文はコマンドとして扱いません。一方、`env -i`のようなオプション付きwrapper、`bash -c '…'`のような引用された入れ子コマンド、変数から組み立てるコマンド、PowerShell構文は検出対象ではありません。hookイベントが不正、引用符の解析に失敗、またはhere-documentのdelimiterを確定できない場合も実行を許可します。その場合は`gh auth status -h github.com --json hosts`を直接実行してください。hookはJSON結果を解釈せず、認証状態の分類、login、refreshも行いません。

### Codex CLIの更新

通常のCodex CLIはAquaで管理します。
更新するときは`aqua update codex`で`aqua.yaml`を更新し、差分を確認してコミットした後に`aqua install`を実行します。

Aqua管理の`codex`に対して`codex update`は使用しません。
`codex update`はstandalone版など導入方式を認識できる実体向けの更新経路であり、Aquaの宣言とGit管理を経由しないためです。

WSLでの具体的なコマンドは、[`codex-wsl/SETUP.md`](codex-wsl/SETUP.md)の「通常CLIを更新する」を参照してください。

## Windows

### Git Bash で SSH 接続時に psmux へ復帰する

Git Bash を Windows OpenSSH の既定シェルにした環境では、対話型の SSH 接続から `psmux -L dotfiles-ssh new-session -A -s ssh` を実行します。
SSH 専用の名前空間 `dotfiles-ssh` に `ssh` がなければ作成し、あれば既存セッションへアタッチします。
ローカル用の `main` と分離し、既存のセッションや作業は削除・改名しません。
psmux 内のシェルは既存の `.psmux.conf` に従って Git Bash を使います。
`Ctrl+b` の後に `d` でデタッチすると、接続元の Git Bash に戻ります。
セッションを終了する `exit` や `kill-session` は、再接続まで作業を残したい場合には使いません。

chezmoi が配置する `.bashrc` のランチャーから通常の設定を読み込み、端末の `.bashrc.local` の後に `.bashrc.ssh-psmux` を実行します。
Windows の Bash、対話フラグ、SSH 接続情報、標準入力と標準出力の端末判定がそろったときだけ起動します。
`bash -c` / `bash -ic` のコマンド、入れ子の Bash、既存の tmux/psmux 内、ローカルシェル、パイプ接続では起動しません。
psmux が見つからない場合や起動に失敗した場合は、エラーを表示して Git Bash を続行します。

SSH 専用設定は、chezmoi が配置する `~/.bashrc.ssh` のランチャーを介してリポジトリの `.bashrc.ssh` から読み込みます。
`CODEX_HOME="$HOME/.codex-personal"` を設定し、Termius の環境変数送信や `AcceptEnv CODEX_HOME` には依存しません。
`GH_CONFIG_DIR="$HOME/.config/gh-ssh"` を SSH と Windows psmux 内で共通に使い、psmux 外の通常の GitHub CLI 認証設定と分離します。
初回認証は [SSH 専用の GitHub CLI 認証](README.manual.md#ssh-専用の-github-cli-認証)に従い、保存先の ACL を確認してから実行してください。
Windows psmux 内では、空でない `PSMUX_SESSION` または `TMUX` の `/tmp/psmux-` ソケットパスで判定し、`main`、`ssh`、warm ペインなど全セッションに個人用設定を適用します。
セッション名、ソケットの名前空間、`SSH_CONNECTION` の有無には依存せず、入れ子の Bash、非対話コマンド、パイプでも同じ設定を使います。
これらの環境変数は実行コンテキストの目印であり、認証やセキュリティ境界の証明ではありません。
psmux 外の通常のローカルシェルと非対話 SSH コマンドでは上書きしません。
psmux のペインから起動した子プロセスは、この環境を継承します。
自動アタッチを回避しても、対話型の SSH シェルには専用設定を適用します。
`~/.bashrc.ssh` が未配置なら警告して自動アタッチを見送るため、次の対象を差分確認後に適用してください。

```powershell
chezmoi diff "$HOME\.bashrc" "$HOME\.bashrc.interactive" "$HOME\.bashrc.ssh" "$HOME\.psmux.conf" "$HOME\.bash_profile"
chezmoi apply --exclude=scripts "$HOME\.bashrc" "$HOME\.bashrc.interactive" "$HOME\.bashrc.ssh" "$HOME\.psmux.conf" "$HOME\.bash_profile"
chezmoi verify --exclude=scripts "$HOME\.bashrc" "$HOME\.bashrc.interactive" "$HOME\.bashrc.ssh" "$HOME\.psmux.conf" "$HOME\.bash_profile"
```

既存ペインには `source ~/.bashrc` で反映できます。通常の設定を再読み込みした後も個人用設定を再適用します。
起動済みの Codex などのアプリケーションには自動反映されないため、更新済みのペインから起動し直してください。
`printf '%s\n' "$CODEX_HOME" "$GH_CONFIG_DIR"` で `.codex-personal` と `.config/gh-ssh` を確認してください。
新しいウィンドウ・分割ペインと、切断後の再接続でも確認します。
必要な作業は `main` に残して保存・終了を個別に判断してください。

既定シェルの変更は管理者による手動設定です。
`chezmoi apply` は OpenSSH のレジストリ、`sshd_config`、鍵、認証方式を変更しません。
[README.manual.md の Windows SSH 手順](README.manual.md#windows-ssh-の既定シェルと-psmux)に従い、別接続での確認と復旧手段を確保してから切り替えます。
OpenSSH 9.5 系には Git Bash と PTY なしの `ssh -T host` の組み合わせに[既知の報告](https://github.com/PowerShell/Win32-OpenSSH/issues/2354)があるため、この設定を非対話 SSH まで検証済みとは扱いません。
PTY 付きのリモートコマンドには引用符の制約もあるため、[実機確認した回避方法](README.manual.md#pty-付きリモートコマンドの引用符)を参照してください。

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
