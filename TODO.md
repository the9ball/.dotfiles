# TODO

レビューで保留・実装待ちになっている項目を記録する。

## 実装待ち

- [ ] **U2-R008: Codex defaultsの所有範囲を整理する**
  - defaultsからplugin/MCP宣言を削除し、現在のlive設定は保持する。
  - `chezmoi diff`で適用前に確認する運用を維持する。
- [ ] **U3-R001: WSLディストリビューション指定を揃える**
  - `wsl-codex-exec`をWSLの既定ディストリビューション契約に合わせる。
- [ ] **U3-R002: WSL runnerの起動方法を固定する**
  - Windows側のファイル実行権限に依存せず、`/bin/bash`経由でrunnerを呼び出す。
- [ ] **U3-R004: Windows launcherの失敗経路を補強する**
  - `SCRIPT_PATH_WSL`を変換前にクリアし、`wslpath`の終了コードを検証する。

## 後日確認

- [ ] **Remote Controlの互換性を確認する**
  - Aqua管理版の`codex remote-control start`と、standalone版の導入・更新・起動ライフサイクルを比較する。
  - Remote Controlのデーモン起動やstandaloneインストーラーの実行は、明示的に再開するまで行わない。
