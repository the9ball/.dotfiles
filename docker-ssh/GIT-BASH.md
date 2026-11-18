# Git Bashでの利用

SSHの親子プロセスへ自動適用する0.5系は [ISSUE-185.md](ISSUE-185.md) を参照する。
以下は引き続き利用できる明示的な手動入口であり、別途起動するnative子プロセスへactivate関数を継承するものではない。

手順の正本は [INSTALL.md](INSTALL.md)。公開ランチャーのsourceと、明示deploymentへのactivationだけを行う。
通常のDocker Desktop設定は変更しない。`docker-ssh-deactivate`でshellの選択を戻す。

Docker CLIは絶対パスから起動し、専用DOCKER_CONFIG・HelperのPATHを子プロセスにだけ渡す。
named pipeのMSYS変換を除外し、通常ファイル引数の変換を保つ。
Docker endpoint/context/configのoverrideと短縮option連結は拒否する。

新規SSHは接続元の環境変数・関数や既存psmuxを再利用せず、各接続で同じ端末の公開source/activateを実行する。
profile自動変更やtokenの環境変数常時供給はしない。
PATは非表示入力からpassword-stdinへ渡す。Helperのget結果を端末へ表示しない。

実別Windows、再起動後GUI未ログオン、Engine明示起動、private registry操作の試験を分離する。
[VALIDATION.md](VALIDATION.md)に前提と期待結果・停止条件を記載する。
