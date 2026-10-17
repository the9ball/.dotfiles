# .dotfiles統合の範囲

## 対象と除外

DockerCredentialTpm 0.4.0、TpmKeySetup 0.4.0、共有PCP Policy、端末別setup/removal、公開ランチャー、限定された試験を移植する。
暗号化・用途・ACL・ストレージ形式は変更しない。
`poc-tpm-v2/Policy.cs` は本番key toolが参照する共有実装として残す。旧PoC実行プログラムは含めない。

既存ホストの設定、鍵、binding/receipt、vault、実トークン、生成バイナリ、ログ、GHCR操作script、古い固定試験IDのreader、DPAPI/KDBX試作は取り込まない。
`chezmoi/AppData/Local/Dotfiles/DockerSsh/*.tmpl` はモジュール内の公開ファイルをincludeするだけ。
通常のapplyは鍵や資格情報を作らない。実HOMEへのapplyは今回実行しない。

## 実装と検証の区分

1. 検証済み実装の移植：既存26ファイル。ロジック追加0行、暗号実装変更0。
2. 公開4ファイルのchezmoi橋渡し、前提検査、導入手順：実装50〜100行。新しい秘密保管方式・自動初期化hook・依存package追加0。
3. 隔離HOME・source portability・無変更再適用の自動検査：試験コード100〜180行を別枠とする。
4. 独立読み取りレビューとIssue報告。新しいTPM鍵、実資格情報、Docker Engine操作は0回。

新規抽象化は前提検査のprovider-only probe 1クラス、設定項目追加0。新規ファイルの実数・hashは提出時manifestで照合する。
ローカルモック/CheckOnly成功を別Windows実機成功や再起動比較成功と表現しない。

既存ホストのF1/G1/H1、build、image差し替え、ChatGPT直接接続は[Issue #142](https://github.com/the9ball/.dotfiles/issues/142)の履歴にある。
その再試験や更新・停止は今回の対象外。

## 承認候補

- ?1：別Windowsへの恒久鍵作成・初期化・実トークン登録。端末とレジストリを特定して承認する。
- ?2：別Windowsの手動再起動とGUI未ログオンSSH比較、必要時のEngine起動。作業中断と既存コンテナ再開の影響を確認する。
- ?3：鍵削除を伴う完全撤去、token失効・package削除など。不可逆のため対象を照合する。
- ?4：Git push / PR。送信ブランチ・差分を提示して別途承認する。
