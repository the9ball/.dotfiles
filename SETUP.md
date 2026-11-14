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
# 初回だけ、リポジトリを明示してchezmoiの設定を生成する
cd "$HOME/.dotfiles"
chezmoi --source "$HOME/.dotfiles" init
chezmoi diff
chezmoi apply
chezmoi verify --exclude=scripts
~~~

初回の`init`以後は、リポジトリのルートを明示せず`chezmoi diff`、`chezmoi apply`、`chezmoi verify --exclude=scripts`を実行できます。

Codex Desktopのプロジェクトと関連フォルダーの設定は、アプリで行います。
`~/.codex/.codex-global-state.json`はchezmoiの管理対象から除外しています。

`chezmoi apply`は、次の処理を実行します。

- 設定ファイルの変更前に`aqua-policy.yaml`のSHA-256を検証し、固定した確認済みの値と一致する場合だけ`aqua policy allow`を実行する。
- `aqua install`：`aqua.yaml`に定義されたCLIを導入する。
- `uv python install`と`uv pip install`：Python 3.13とPyYAML 6.0.3を導入する。
- Windows：`winget import`で`winget.json`に定義されたAWS CLI、aws-vault、WinMerge、CPU-Z、Cryptomator、WinFspを導入する。
- `prek install`：Git hookを設定する。
- `.bashrc`、`.bashrc.interactive`、`.gitconfig`をホームディレクトリへ配置する。
- `link-targets/agents`、`link-targets/agents/skills`、`link-targets/claude/agents`、`link-targets/claude/mods`を、それぞれ`~/.agents`、`~/.claude/skills`、`~/.claude/agents`、`~/.claude/mods`へ共有リンクとして公開する。

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

## ローカルでの構文・設定チェック

リポジトリのルートで、push 前に次を手動実行します。
Windows では Git Bash、WSL では WSL 内のシェルから実行してください。
チェック定義は `.pre-commit-config.yaml` に集約しており、ShellCheck（Bash / POSIX sh）、POSIX sh の構文、JSON / YAML / TOML のパース、GitHub Actions の構文を検査します。
GitHub Actions の [CI ワークフロー](.github/workflows/ci.yaml) も、master を base とする PR と master への push で、同じ定義と次のコマンドを実行します。
ワークフロー自体も actionlint の検査対象です。

```sh
prek run --all-files --stage manual
```

POSIX sh の構文チェックは Windows では Git Bash 内の `/bin/sh`、Ubuntu CI では runner の `/bin/sh` を使います。
`System32/bash.exe`（WSL ランチャー）の PATH 順序には依存しません。
Git Bash の `sh` が PATH にある環境で実行してください。

Bash の対象は ShellCheck の `-s bash` で構文と lint を検査し、同じ対象への `bash -n` フックは重複分として外しています。
POSIX sh の `-s sh` は移植性の検査で、実際のシステムシェルの受理判定とは異なるため、`sh -n` は残します。
ShellCheck と native parser は完全に同等ではなく、構文診断をコメントで抑止すると ShellCheck が通る場合もあります。
通常の構文破損を ShellCheck が検出することは確認していますが、Bash 診断を抑止する変更は修正担当とレビュー担当が確認してください。
native Bash の構文判定も必要な場合は、対象を指定して手動実行できます。

```sh
sh scripts/check-files.sh bash-syntax path/to/script.sh
```

push 時にも実行したい人だけ、次で pre-push フックを導入します。
通常の `prek install` が導入する pre-commit ステージでは、追加した構文・設定チェックは実行せず、既存の gitleaks フックだけを実行します。

```sh
prek install -t pre-push
```

pre-push フックが検査するのは、push するコミットで変更されたファイルだけです。
全ファイルを検査したい場合は、上の manual ステージの手動実行を使います。

`prek`、`shellcheck`、`jq`、`yq`、`actionlint`、`gitleaks` が PATH にない場合は、リポジトリのルートで `aqua install` を実行し、Aqua の bin を PATH に追加してから再実行します。
ローカルレジストリの承認が必要な場合は、上の Aqua 導入手順を参照してください。
WSL でも WSL 側の Aqua とツールを用意します。
一部のツールが動かない実行環境もあるため、pre-push の導入は任意です。
利用できないツールのチェックは、その環境で検証済みとは扱いません。

通常の構文チェックではテンプレート（`*.tmpl`、chezmoi の `.chezmoitemplates/`、`modify_*`、`create_*`）と外部取り込みの `git-completion/` を除外します。
テンプレートは `chezmoi-templates` フックで Linux / Windows のダミーデータを使って展開し、展開エラーと JSON / TOML のパースエラーを検出します。
named helper は実際の wrapper から読み込み、静的な `create_AGENTS.md` の配置は検査しません。
`.chezmoiexternal.toml` も展開後に TOML として検査しますが、外部ファイルは取得しません。

このフックには `python3` として実行できる Python 3.11 以上（標準ライブラリの `tomllib` を使用）、事前導入済み chezmoi の実体パスを指定する `CHEZMOI_TEST_BINARY`、Git が必要です。
Python は CI の Ubuntu 24.04 runner に標準搭載されたものを使い、追加の Python package や setup Action は導入しません。
ローカルでは Python 3.11 以上を用意し、ツール導入時に以下を実行してください。
`aqua which` は registry の取得・更新を伴うことがあるため、導入工程でだけ呼び出します。

```sh
aqua install --tags ci
export CHEZMOI_TEST_BINARY="$(aqua which chezmoi)"
```

PowerShell では、導入後に `$env:CHEZMOI_TEST_BINARY = (aqua which chezmoi).Trim()` と設定します。
この値は信頼できる事前導入済みの実体を指定する契約で、PATH 上の Aqua shim や別の実行ファイルは指定しません。
CI もツール導入ステップ内で解決した実体パスだけを後続へ渡します。
チェッカーは Aqua を呼ばず、変数が未指定または実体が存在しない場合はダウンロードせずに失敗します。
子プロセスには `AQUA_DISABLE_LAZY_INSTALL=true` も渡しますが、これは package の遅延取得に対する補助で、shim による registry 取得までを防ぐものではありません。
単体で実行する場合も共通の入口を使います。

```sh
prek run chezmoi-templates --all-files --stage manual
```

追跡済みの作業ツリー入力だけを一時 source にコピーし、HOME 系の環境変数・config・state・cache を一時領域に向けます。
認証変数を子プロセスへ渡さず、実 HOME の設定、未追跡のホスト用 `.local`、外部ファイル取得に依存しません。
setup script や hook、`apply` は実行しません。
生成結果の設定値・動作の正しさは修正担当とレビュー担当が確認し、新しい意味的回帰テストは追加していません。
Windows の OS 値を渡す試験はネイティブ実行・配置の保証ではなく、それらは Phase 3 の対象です。
一時 HOME は悪意あるテンプレート関数の sandbox ではなく、OS レベルの通信遮断も行いません。

### Codex 設定の回帰テストを手動実行する

`tests/codex-config.py` の既存 6 テストは、モデル名・権限・既存値保持・ローカル上書き・冪等性などを検査します。
必須 CI と `chezmoi-templates` フックからは実行せず、Codex 設定を修正・レビューするときに手動で実行します。
上記のツール導入手順で `CHEZMOI_TEST_BINARY` を設定してから、リポジトリのルートで次を実行してください。

```sh
python3 -B tests/codex-config.py -v
```

テスト自体が source・destination・config・state・cache を一時領域に作り、実設定の代わりに synthetic な既存値と `.local` を使います。
6 テストの内容は維持し、失敗またはスキップが発生した場合は非0で終了します。

### gitleaks と必須 CI

既存の gitleaks フックはステージ済みの差分を対象とします。
push 前にコミット範囲を走査する場合は、別途次を手動実行します。
比較先の `origin/master` が意図した基準か確認し、必要に応じて範囲を変更してください。

```sh
gitleaks git --redact --log-opts="--diff-merges=first-parent origin/master..HEAD"
```

CI では、上の構文・設定チェックとは別に `gitleaks git --redact` でイベントのコミット範囲を走査します。
ローカルのステージ済み差分の検査と異なり、PR は base と PR head の merge-base（起点を含まない）から PR head まで、master への push は `github.event.before`（起点を含まない）から `github.sha` までが対象です。
PR の構文・設定チェックは checkout が用意するマージ結果を検査します。
gitleaks は PR head までの履歴に加え、GitHub Actions の synthetic merge commit を1件だけ追加走査します。
両方の走査で `--diff-merges=first-parent` を指定し、マージ時に追加された変更も親1との差分で検査します。
履歴の辿り方を制限する `--first-parent` は使わず、通常コミットや side branch で追加後に削除された秘密も走査対象に残します。
checkout は `fetch-depth: 0` とし、範囲は Bash スクリプト [`scripts/ci-gitleaks-range.sh`](scripts/ci-gitleaks-range.sh) で計算します。
引数はイベント名（`pull_request` / `push`）、比較元の完全なコミット SHA、走査先の完全なコミット SHA です。PR では第4引数にイベントの merge SHA（`github.sha`）も必須です。
PR の merge SHA は checkout HEAD と一致し、実在するコミットで、親がちょうど2件、親1がイベントの base SHA、親2が head SHA であることを範囲の出力前に検証します。
SHA の欠落・全桁ゼロ・存在しないコミット、浅い履歴、merge-base の欠落・複数候補、push の比較元が head の祖先でない場合、履歴の取得・比較・走査の失敗は CI を失敗させます。
merge SHA・親・checkout HEAD の不一致も失敗です。別の ref や全履歴を代わりに走査したり、検査をスキップして成功にしたりしません。
CI で秘密情報を検出した時点で内容は remote に到達しているため、漏えいとして該当の認証情報を無効化・差し替えます。

CI の検査ジョブは GitHub-hosted の `ubuntu-24.04` で動き、集約ジョブのチェック名は `ci-required` です。
集約ジョブは `always()` で実行し、`needs` に依存ジョブが 1 つ以上あり、すべての結果が `success` の場合だけ成功します。
`failure` / `cancelled` / `skipped` は失敗として扱います。
このチェックを ruleset に登録する作業は別途行います。

Aqua 本体は公式の aqua-installer Action で導入し、自動の全ツール導入は無効にします。
既存の chezmoi スクリプトと同じ固定 SHA-256 を照合してから `aqua policy allow aqua-policy.yaml` を実行します。
`aqua.yaml` の `ci` タグを持つ prek、shellcheck、jq、yq、actionlint、gitleaks、chezmoi の 7 パッケージだけを `aqua install --tags ci` で事前にダウンロードします（リンクだけを作る `-l` は使いません）。
読み取り専用の `GITHUB_TOKEN` はこのツール導入ステップの環境変数にだけ渡し、aqua-installer へのトークン入力は空にします。
prek と gitleaks の実行ステップには渡しません。
Aqua 本体と導入したツールは、`actions/cache` で `~/.local/share/aquaproj-aqua` ごとキャッシュします。
キーには runner の OS・アーキテクチャ、Aqua 本体のバージョン、`aqua.yaml` と `aqua-registry.yaml` のハッシュを含めるため、どれかが変わると新しいキャッシュになります。
PR の CI は master で保存されたキャッシュを読めますが、PR で保存したキャッシュはその PR からしか読めません。
Aqua の自動更新ワークフローは、master の CI が保存した同じキャッシュを読み込むだけで、書き込み権限を持つため保存はしません。
GitHub Releases が一時的に 5xx を返し続けた場合に備え、aqua-installer は失敗時に 1 回だけ再実行し、`aqua install --tags ci` も 1 回だけ再試行します。待機時間は入れません。
構文・設定チェックと秘密情報の走査は、ツールの導入に成功していれば互いの結果にかかわらず両方実行します。どちらかが失敗すればジョブは失敗し、`ci-required` も失敗します。
必要なツールをすべて事前導入するため、後続ステップで Aqua の遅延ダウンロードを必要としない構成です。実際のダウンロードの有無は CI 上で確認します。
ただし、CI の `prek run --all-files --stage manual` 実行時には、prek が `.pre-commit-config.yaml` に指定されたリモートフックのリポジトリ（`https://github.com/gitleaks/gitleaks`、`v8.30.1` に対応するコミット SHA `83d9cd684c87d95d656c1458ef04895a7f1cbd8e` に固定）を取得します。
manual ステージでは gitleaks フックを実行しませんが、取得自体は発生し、この取得にトークンは使いません。

gitleaks を更新するときは、`gitleaks-system` フックが使う実行ファイルのバージョン（`aqua.yaml` の `gitleaks/gitleaks@v8.30.1`）と、フック定義の取得元（`.pre-commit-config.yaml` の `rev` と `# frozen:` コメント）を同じバージョンに揃えて更新します。
対象タグが指すコミットは、次のコマンドで確認します。更新時は `v8.30.1` を対象のタグに置き換えます。

```sh
gh api repos/gitleaks/gitleaks/git/ref/tags/v8.30.1 --jq '.object | {type, sha}'
```

`type` が `commit` なら、表示された `sha` を `rev: <SHA>  # frozen: <タグ名>` の形式で設定します。
`type` が `tag`（注釈付きタグ）なら、`gh api repos/gitleaks/gitleaks/git/tags/<表示されたSHA> --jq '.object | {type, sha}'` で参照先をたどり、`type` が `commit` になった時点の `sha` を使います。

CI には次の残留リスクがあります。

- gitleaks は Git の差分を走査します。マージ差分を有効にしても、未変更行を含む複数行の合成パターンなど、最終ファイル全体で初めて成立する秘密を完全には検出できません。リポジトリ全体の snapshot 走査は行いません。
- PR の走査対象はその実行時の synthetic merge です。後の base 更新や実マージ時の追加修正まで保証しないため、master への push の履歴・マージ差分走査も維持します。
- PR で `.github/workflows/*`、`.pre-commit-config.yaml`、`scripts/`、`aqua.yaml`、`aqua-registry.yaml`、`aqua-policy.yaml` などを書き換えると、runner 上で任意のコマンド実行や外部通信が起こりえます。policy の照合処理も書き換えられるため、信頼境界にはなりません。
- PR で `.gitleaks.toml` や `.gitleaksignore` を追加または変更すると、gitleaks の検出を抑止できます。
- `pull_request` を使い、`permissions` は `contents: read` のみ、checkout は `persist-credentials: false` とし、ワークフローは secrets を参照しません。fork PR は GitHub 側の権限制約と実行承認の設定を境界にします。同一リポジトリからの PR と push では、ワークフローの書き換えにより書き込み権限や設定済みの secrets に届くリスクが残ります。Actions の既定トークン権限を read にしても上限にはなりません。このリスクは当面受容し、[Issue #208](https://github.com/the9ball/.dotfiles/issues/208) で見直します。
- `aqua.yaml` の checksum 検証は無効のままです。今回の CI 追加では有効化していません。
- policy の固定 SHA-256 は、既存の `run_before_00-aqua-policy.ps1.tmpl` / `run_before_00-aqua-policy.sh.tmpl` と CI ワークフローで二重管理します。policy を変更するときは、内容を確認したうえで双方の固定値を更新します。

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

Windows OpenSSH Serverはaqua管理外です。新規端末ではWindows標準のオプション機能を基本の選択肢とします。
[Windows OpenSSHの運用記録](docs/windows-openssh.md)に、標準版と、明示的に承認した端末限定のZIP版運用の分岐、検証範囲、復旧参照をまとめています。
ZIP版10.0.0.0p2-Previewの結果は検証した端末・経路に限定し、別端末への展開や任意のSSH機能の保証には使いません。

cloudflaredのWindowsサービスを使う端末では、初回に管理者権限でのセットアップが必要です。以降は`chezmoi apply`がaquaのバージョン更新にサービスを追従させます。
手順と経緯は[Windows cloudflaredサービスの更新](docs/windows-cloudflared.md)を参照してください。

既定シェルの変更は管理者による手動設定です。
`chezmoi apply` は SSHサーバーの導入・更新・サービス操作や、OpenSSH のレジストリ、`sshd_config`、鍵、認証方式の変更を行いません。
[README.manual.md の Windows SSH 手順](README.manual.md#windows-ssh-の既定シェルと-psmux)に従い、別接続での確認と復旧手段を確保してから切り替えます。
OpenSSH 9.5 系には Git Bash と PTY なしの `ssh -T host` の組み合わせに[既知の報告](https://github.com/PowerShell/Win32-OpenSSH/issues/2354)があります。
この手順だけで、コマンドなしの非PTY接続や任意のリモートコマンドまで検証済みとは扱いません。Issue #144のZIP版で確認した非PTYコマンドは`true`の終了0です。
PTY 付きのリモートコマンドには引用符の制約もあるため、[実機確認した回避方法](README.manual.md#pty-付きリモートコマンドの引用符)を参照してください。

### 再起動後にアプリの再認証が毎回求められる場合

Microsoft アカウントに Windows Hello（PIN・顔）だけでサインインしている端末で、再起動後に CurrentUser DPAPI のマスターキーを取得できなくなった事例があります。
Claude Desktop などの保存済みログインを復号できず、再ログインしても保存できないため、アプリを起動するたびに再認証になります。
SSH ログオンだけでなく GUI ログオンでも発生し、[Issue #142](https://github.com/the9ball/.dotfiles/issues/142) の検証中に見つかりました。
dotfiles や SSH の設定変更が原因とは確認されていません。

次のコマンドが `0x80070005` などで失敗し、イベントログ `Microsoft-Windows-Crypto-DPAPI/Operational` にイベント 3（Master key access failed）と 8198 が並んでいれば該当します。

```powershell
Add-Type -AssemblyName System.Security
[Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes('probe'), $null, 'CurrentUser').Length
```

本人が次の手順で復旧します。スクリプトや chezmoi では自動化しません。

1. 設定 → アカウント → サインイン オプションで「Microsoft アカウント用に Windows Hello サインインのみを許可する」をオフにします。
2. 再起動するか Ctrl+Alt+Del からサインアウトします。画面ロックからの復帰では新しいログオンにならず、復旧しません。
3. サインイン オプションで鍵アイコンを選び、Microsoft アカウントのパスワードでサインインします。

この手順で既存のマスターキーも復号できるようになり、保存済みのログインは失われませんでした。
根本原因は未確定のため、Hello だけのサインインに戻す場合は、再起動して PIN でサインインした後も上記コマンドが成功することを確認してください。

Windows x64ではAWS CLIとaws-vaultがAquaの対象外になるため、wingetで導入します。
AquaにないGUIアプリのWinMerge、CPU-Z、Cryptomatorも、Windowsではwingetで導入します。
WinFspは、CryptomatorがWindowsで保管庫をドライブとしてマウントするために使うため、あわせて導入します。
Linux、macOSではwingetを実行せず、AWS系も含めてAquaで導入します。

WSL版Codex Remote Controlを使う場合は、[`codex-wsl/SETUP.md`](codex-wsl/SETUP.md)を上から順番に実行します。
`.codex-wsl`の詳細は、同文書から[`codex-wsl/CODEX_HOME.md`](codex-wsl/CODEX_HOME.md)へ進みます。

WSL側の`CODEX_HOME`は`$HOME/.codex-wsl`に分けます。
Windows側の`CODEX_HOME`と同じ物理ディレクトリを参照することは可能ですが、現在のWindows設定にはWSLで解釈できないパスが含まれています。
WSL固有の`AGENTS.md`を置き、Windows側の設定、ログ、セッション、SQLite状態を分離するため、現在は別ホームを使います。

以後、コミット時に`.pre-commit-config.yaml`のgitleaksフックが実行されます。

Agent Skillsの導入手順は、[`README.manual.md`](README.manual.md)の「Agent Skillsの導入」を参照してください。
Datadog MCPの設定手順は、同じ文書の「Datadog MCPの設定」を参照してください。

## Windows SSH 専用 Docker 認証（任意）

TPM を使う独立した認証環境の導入は [docker-ssh/INSTALL.md](docker-ssh/INSTALL.md) を参照してください。通常の chezmoi 適用は公開ランチャーだけを配置し、鍵作成・資格情報登録・Docker 設定変更は行いません。
