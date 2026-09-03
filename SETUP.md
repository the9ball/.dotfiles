# セットアップ

chezmoiは設定ファイルの配置に加えて、各パッケージマネージャーを呼び出します。
通常は`chezmoi apply`だけを実行します。

## 共通

```sh
chezmoi apply
```

`chezmoi apply`は、次の処理を実行します。

- `aqua install`: `aqua.yaml`に定義されたCLIを導入
- `uv python install` と `uv pip install`: Python 3.13とPyYAML 6.0.3を導入
- Windows: `winget import`: `winget.json`に定義されたAWS CLIとaws-vaultを導入
- `prek install`: Git hookを設定
- `.bashrc`と`.gitconfig`をホームディレクトリへ配置
- `.agents`と`.claude/skills`の共有リンクを作成

Python 3.13とPyYAML 6.0.3は、`run_onchange_after_tools`スクリプトの初回実行時に導入します。スクリプトの内容が変わった場合や前回の実行に失敗した場合を除き、通常の`chezmoi apply`では不足分の再導入を行いません。

## Windows

Windows x64ではAWS CLIとaws-vaultがaquaの対象外になるため、wingetで導入します。
Linux/macOSではwingetを実行せず、AWS系も含めてaquaで導入します。

以後、コミット時に`.pre-commit-config.yaml`のgitleaksフックが実行されます。

Agent Skillsの導入手順は、[`README.manual.md`](README.manual.md)の「Agent Skillsの導入」を参照してください。Datadog MCPの設定手順は、同じ文書の「Datadog MCPの設定」を参照してください。
