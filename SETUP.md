# セットアップ

chezmoiは設定ファイルの配置に加えて、各パッケージマネージャーを呼び出します。
通常は`chezmoi apply`だけを実行します。

## 共通

```sh
chezmoi apply
```

`chezmoi apply`は、次の処理を実行します。

- `aqua install`: `aqua.yaml`に定義されたCLIを導入
- Windows: `winget import`: `winget.json`に定義されたAWS CLIとaws-vaultを導入
- `prek install`: Git hookを設定
- `.bashrc`と`.gitconfig`をホームディレクトリへ配置
- `.agents`と`.claude/skills`の共有リンクを作成

## Windows

Windows x64ではAWS CLIとaws-vaultがaquaの対象外になるため、wingetで導入します。
Linux/macOSではwingetを実行せず、AWS系も含めてaquaで導入します。

以後、コミット時に`.pre-commit-config.yaml`のgitleaksフックが実行されます。
