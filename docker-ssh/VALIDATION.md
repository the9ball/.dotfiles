# 別Windows 11で必要時に行う検証

## Issue #185の0.5系実装

SSH自動選択・OAuth対応は [ISSUE-185.md](ISSUE-185.md) を参照する。
ソースと隔離試験の段階であり、host反映・実TPM/実認証・再起動検証は別承認で未実施。
以下のIssue #142の実績は0.4系の履歴であり、0.5系の成功を意味しない。

**別Windows実機：未実施・必要時に検証。** 今回のIssue #142の必須完了条件には含めない。以下は将来の再現用手順であり成功の報告ではない。
将来の担当モデルは、本書、[INSTALL.md](INSTALL.md)、実装、その時点の最新公式仕様を参照して、対象端末に必要な試験を選ぶ。
今回の判定は [ACCEPTANCE.md](ACCEPTANCE.md)、方針変更の履歴は [VALIDATION.history.md](VALIDATION.history.md) を参照する。
このホストの恒久鍵やstoreをコピーせず、対象端末で新しい鍵とダミー/端末用tokenを初期化する。

## 変更なしの検証

信頼したチェックアウト、Windows 11 x64、TPM/PCP、PowerShell 7.4以上、.NET 10 SDK/runtime、Git Bash、Docker Desktop Linux Engine、OpenSSH serverを用意する。
Node 22以上とchezmoiは自動テスト用。既存configの有無とhashを秘密非表示で記録する。

リポジトリルートで次を実行する。鍵作成、実registry、Engineの起動/停止は行わない。

`````bash
node tests/docker-ssh-integration.mjs
cd docker-ssh
pwsh.exe -NoProfile -File scripts/Test-TpmPrerequisites.ps1 -Purpose Test
node tests/Verify-TpmSetup.mjs --authorization-self-test
node tests/Verify-TpmSetup.mjs
node tests/Verify-TpmStaging.mjs
node tests/Verify-TpmLaunchers.mjs
`````

末尾の3コマンドはpackage/無害なprobeのビルドと専用一時HOME/配置にだけ書き込む。
authorization引数なしのVerify-TpmSetupはCheckOnlyとprovider到達前の拒否経路だけで、鍵作成0回。
Verify-TpmStagingは不存在の公開bindingを使い、配置/再適用/無効な撤去ID拒否/専用試験配置の撤去を行う。
Verify-TpmLaunchersは非ASCIIパス、UTF-8のpipe、誤configパス、routing/hash/ACL/状態不一致と厳密なID検査を試験する。Docker/Helperの代わりにTPM機能を持たないprobeを使い、実Dockerや鍵には触れない。
いずれも結果不明/timeoutなら停止し、残存する自分の試験物を確認してから次へ進む。
モック・一時HOME成功を別マシンのTPM利用成功とはしない。

## ダミー4操作と端末別初期化

対象端末で1回用のPoC鍵作成・削除を承認する場合だけ、Verify-TpmSetupの明示authorizationを使用できる。
このファイルは自動生成して承認扱いにしない。レビューしたファイル群とhash、SID、InstallationId、鍵名、実行範囲を確認して記入する。

- InstallationIdは新しいGUIDの32桁小文字hex。
- Mode=poc、MaxKeys=1、AllowCreateAndExactDelete=true、State=APPROVED_ONE_TRIAL。
- UserSidは対象端末の実行ユーザー。KeyNameはdocker-ssh-issue142-poc-とInstallationId。
- DestinationRootはその端末のLocalAppData直下のdocker-ssh-issue142-lab-install-とInstallationId。
- FilesはVerify-TpmSetup.mjsのreviewedFilesに列挙されたファイル全件と実際のSHA-256。欠落・重複・変更を拒否する。

`````bash
node tests/Verify-TpmSetup.mjs 'ABSOLUTE_PATH_TO_REVIEWED_AUTHORIZATION.json'
`````

期待結果は空store、dummy store/get/list/update/erase、再実行不変、disable/cleanupの各PASS。
鍵削除API成功と、別照会の不存在を別々に確認する。削除失敗なら残存物を保持し、新しい鍵を作らない。
このPoCは試験終了時に撤去されるため、再起動後の同一暗号文比較には使えない。

恒久配置は [INSTALL.md](INSTALL.md) のCheckOnly後、別承認した新しいInstallationIdで初期化する。
初期化完了後に同じ入力で再実行し、同じ鍵・receipt・storeを保持して照合のみで成功することを確認する。
異なる配布物hashや識別情報、初期化未完了の空ディレクトリは拒否することが期待結果。
既存READY配置への再実行は配布10ファイルと選択settingsの限定照合であり、vault/config/binding等や未知ファイルの全件検査ではない。CheckOnly成功だけで完全性を判定しない。
未知ファイルは完全撤去時のallowlist検査では拒否する。現行の既存storeを壊して試験しない。

## 新規SSHと再起動比較

実registry試験には対象private imageのdigest、アカウント権限、短期token期限、既存image/containerへの影響を事前に承認する。
公開imageの匿名pull成功だけでは認証の証明にならない。
tokenは対象端末で登録し、baselineとしてSID・boot時刻・AuthenticationId、key receipt/binding、Helper全4ファイル、vault.tpm、configのSHA-256を秘密非表示で保存する。
hashを含む端末別記録もGitに加えない。秘密のget応答は表示しない。

接続元のGit Bashから新規公開鍵SSHを使う。SSH接続先HOSTと端末のGit Bash絶対パスはその端末で確定し、固定ユーザー名をコピーしない。

`````bash
ssh -T -o ControlMaster=no -o ControlPath=none -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no HOST
`````

default shellがGit Bashでない場合は明示的にGit Bashを起動する。対話SSHでpsmuxに自動attachした結果を新規SSH成功としない。
必要ならリモートコマンドでその端末のGit Bashを指定し、source/activate/infoと承認済みdigestのpullを実行する。
接続形式の引用方法は対象ホストのOpenSSH default shellに依存するため、無害なメタデータコマンドで先に確認する。

GUIログオフ、同一boot再接続、OS再起動後GUI未ログオンを別々に記録する。
再起動比較は利用者が承認した手動再起動1回の前後で同じSID/鍵/暗号文/Helperを照合し、bootが変わったことを確認する。
その端末のPowerShellからtests/TpmSessionEvidence.ps1を読み込みGet-TpmSessionEvidenceでLogonType=3と新しいAuthenticationIdを記録する。
tests/ColdBootEnvironment.ps1のGet-TpmGuiSessionCountでGUI user session 0を確認する。利用者もGUIへログインしていないことを申告する。

順序はTPM資格情報の取得を秘密非表示で検証→Engine info→必要かつ承認済みの場合だけDesktop明示起動→private digest pull最大1回。
Engine不通ならpullは実行せずUNTESTED。PAT期限切れ/不一致/UI/timeout/接続失敗なら自動retryしない。
成功時はpullの終了0とdigest一致、追加login/入力なし、元Desktop設定/profile不変を確認する。
新しいhashのbaselineを作り直して既存暗号文の不一致を隠さない。

## 記録と復旧

PASS/FAIL/UNTESTEDを別々に記録：OS/依存version、TPM初期化、4操作、同一起動SSH、再起動後TPM、GUI0、Engine、private pull、digest、既存config保持。
実際に行っていない更新・TPM喪失復旧・他OSはUNTESTED。
失敗時は鍵や暗号文を再生成せず保持し、部分intent、ACL/reparse、HRESULT、Engine状態を秘密非表示で調べる。
shellのdeactivateで既存Docker Desktop経路へ戻せる。全撤去は公開識別情報を照合して別承認する。

## 承認候補

- ?1：対象別マシンのPoC/恒久鍵作成とダミー操作・専用配置撤去。今回この既存ホストでは実行しない。
- ?2：端末用token登録とprivate image転送。対象・権限・公開範囲を限定する。
- ?3：GUIログオフ/再起動/必要時Engine起動。現在作業中の利用者へ影響を確認する。
- ?4：試験後のtoken/資格情報/image/package削除。恒久鍵と専用環境の保持方針を別々に決める。
