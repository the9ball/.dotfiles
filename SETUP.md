# セットアップ

chezmoiは設定ファイルの配置とテンプレート展開だけを担当します。
パッケージ導入とGit hookの設定は、各環境で明示的に実行します。

## 共通

```sh
chezmoi apply
aqua install --config ~/.dotfiles/aqua.yaml
prek install
```

`aqua install`は、`aqua.yaml`に定義されたCLIを導入します。
Windows x64ではAWS CLIとaws-vaultがaquaの対象外になるため、次のwinget定義で導入します。

## Windows

```powershell
winget import --import-file "$HOME\.dotfiles\winget.json" --no-upgrade --ignore-unavailable --accept-source-agreements --accept-package-agreements
```

## Linux / macOS

Windows専用のwingetコマンドは実行せず、`aqua install`だけを実行します。

## Git hook

```sh
prek install
```

以後、コミット時に`.pre-commit-config.yaml`のgitleaksフックが実行されます。
