# Windows SSH専用Docker認証（TPM）

Windows 11 + Docker Desktop Linux Engine + OpenSSH + Git Bash用のCredential Helper 0.4.0。
検証済み実装をこのリポジトリに取り込んだ。CurrentUser DPAPIや既存Credential Managerは使用しない。

- [導入・更新・撤去・復旧](INSTALL.md)
- [別Windowsで必要時に実施する検証](VALIDATION.md)
- [今回の完了判定と未実施範囲](ACCEPTANCE.md)
- [取り込み範囲と検証記録](INTEGRATION.md)

通常のchezmoi適用は公開ランチャー4個だけを配置する。鍵作成、ストア初期化、認証情報登録、profile変更は行わない。
バイナリ、暗号化ストア、端末別settings・receipt・binding・秘密はGit管理しない。
同じユーザーSIDの任意コード、管理者/SYSTEM、侵害済みOSから秘密を守る方式ではない。

既存ホストでは再起動後GUI未ログオンのTPM取得、SSHからのEngine明示起動、private GHCR pullがPASS。
別Windows実機は未実施・必要時に検証。今回の必須完了条件には含めず、将来の担当モデルが文書・実装・導入時点の最新公式仕様を確認する。
通常のWindows起動だけではEngineが自動起動したとは扱わない。
検証履歴は [Issue #142](https://github.com/the9ball/.dotfiles/issues/142) を参照する。Closeやpush/PRは別承認で実施する。
