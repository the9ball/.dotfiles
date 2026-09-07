# セットアップ

`chezmoi`は設定ファイルの配置と、標準のパッケージ導入を行います。
通常は`chezmoi apply`だけを実行します。

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
chezmoi apply
~~~

`chezmoi apply`は、次の処理を実行します。

- `aqua install`：`aqua.yaml`に定義されたCLIを導入する。
- `uv python install`と`uv pip install`：Python 3.13とPyYAML 6.0.3を導入する。
- Windows：`winget import`で`winget.json`に定義されたAWS CLIとaws-vaultを導入する。
- `prek install`：Git hookを設定する。
- `.bashrc`、`.bashrc.interactive`、`.gitconfig`をホームディレクトリへ配置する。
- `.agents`と`.claude/skills`の共有リンクを作成する。

Linux、macOS、WSLでは、`aqua.yaml`に定義したCodex CLI（`openai/codex`）もAquaで導入されます。
これは通常のCLIの導入であり、Remote Control用standalone版の導入やログインは行いません。

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
