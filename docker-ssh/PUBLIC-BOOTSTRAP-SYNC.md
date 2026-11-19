# 管理SSHの公開bootstrap同期

管理SSHはWindows上で`SSH_CONNECTION`が存在し、`DOTFILES_DOCKER_SSH=required`の場合に必須bootstrapを実行する。
失敗時はシェルを終了する。接続元IPによる分岐はない。
PowerShell 7.5以上を使用する。

| エラーコード | 検査する対象 |
| --- | --- |
| `DSSH_SELECTOR_INVALID` | selectorのパス・JSON・Version・絶対DeploymentRoot、および定義の読込み |
| `DSSH_DEPLOYMENT_INVALID` | 選択deploymentの検証、0.5.0、READY |
| `DSSH_PUBLIC_BOOTSTRAP_INVALID` | 公開bootstrapの存在・パス・ACL・読取り |
| `DSSH_PUBLIC_COPY_MISMATCH` | 公開Enter/Getとcheckout正本の内容不一致 |
| `DSSH_METADATA_INVALID` | 出力メタデータの完全性、出力処理 |

コードは失敗した検証段階を示す。例外全文・秘密値・具体的なパスは出力しない。
後続段階にも問題がある場合、先行する失敗を解消するまで検出されない。
selectorを作り直したり、必須bootstrapや同一性検証を無効化して回避しない。

## 対象と承認候補

正規配置は[INSTALL.md](INSTALL.md)のchezmoi手順で行う。
公開テンプレートは`chezmoi/AppData/Local/Dotfiles/DockerSsh`内にあり、同名の`docker-ssh/chezmoi/AppData/Local/Dotfiles/DockerSsh`正本をincludeする。
`Initialize-DockerSshTpm.ps1`は鍵・ACL・deploymentに作用するため、公開コピーの更新に再実行しない。

?1: `%LOCALAPPDATA%/Dotfiles/DockerSsh`内の既存`Enter-DockerSshEnvironment.ps1`と`Get-TpmDockerEnvironment.ps1`への内容上書き。
事前に対象の絶対パス、固定commit、差分、実行コマンド、バックアップ先と復元方法を提示し、同期の明示承認を得る。
承認前は差分確認までとし、以下の同期ブロックは実行しない。

通常のchezmoi applyはファイル置換によるDACL保持を保証しないため、ACLを変更しない条件では、承認された2つの既存ファイルへ内容だけ上書きする。
selector、settings、manifest、認証、環境設定、他の公開ファイルは対象外。
書込拒否やACL差異があれば停止し、権限・属性を変更しない。
2ファイルの更新は原子的ではない。更新中の新規SSH接続は失敗し得るため、既存接続を維持して実施する。

## 差分確認

信頼したcheckoutのルートからPowerShellで実行する。`git diff --no-index`の終了値1は差分あり、2以上はエラー。

`````powershell
$repository = (Get-Location).Path
$canonicalRoot = Join-Path $repository 'docker-ssh/chezmoi/AppData/Local/Dotfiles/DockerSsh'
$publicRoot = Join-Path $env:LOCALAPPDATA 'Dotfiles/DockerSsh'
$names = @('Enter-DockerSshEnvironment.ps1','Get-TpmDockerEnvironment.ps1')
foreach ($name in $names) {
    git diff --no-index -- (Join-Path $publicRoot $name) (Join-Path $canonicalRoot $name)
    if ($LASTEXITCODE -gt 1) { throw 'Diff failed.' }
}
`````

## 承認後のバックアップと同期

承認対象commit・正本SHA256・公開旧SHA256を固定し、直前に一致を確認する。
以下の`$expectedCommit`と`$expectedHashes`は、承認時に提示した値を設定してから実行する。
`$expectedHashes[$name]`は`Source`と`Target`を持つハッシュ表とする。
両ファイルの事前検査とバックアップが完了するまで公開先へ書かない。

`````powershell
$ErrorActionPreference = 'Stop'
if ((git rev-parse HEAD) -cne $expectedCommit -or $LASTEXITCODE -ne 0) { throw 'Commit changed.' }
$backupRoot = Join-Path ([IO.Path]::GetTempPath()) ('pr292-public-bootstrap-' + [guid]::NewGuid().ToString('N'))
$beforeAcl = @{}
$sourceBytes = @{}
foreach ($name in $names) {
    $source = Join-Path $canonicalRoot $name
    $target = Join-Path $publicRoot $name
    foreach ($path in @($canonicalRoot,$publicRoot,$source,$target)) {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point rejected.' }
    }
    if ((Get-FileHash -LiteralPath $source).Hash -cne $expectedHashes[$name].Source -or
        (Get-FileHash -LiteralPath $target).Hash -cne $expectedHashes[$name].Target) { throw 'Content changed.' }
    $beforeAcl[$name] = (Get-Acl -LiteralPath $target).Sddl
    $sourceBytes[$name] = [IO.File]::ReadAllBytes($source)
}
[void][IO.Directory]::CreateDirectory($backupRoot)
foreach ($name in $names) {
    [IO.File]::WriteAllBytes((Join-Path $backupRoot $name), [IO.File]::ReadAllBytes((Join-Path $publicRoot $name)))
    if ((Get-FileHash -LiteralPath (Join-Path $backupRoot $name)).Hash -cne $expectedHashes[$name].Target) { throw 'Backup content mismatch.' }
}
$beforeAcl | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupRoot 'acl-before.json') -Encoding utf8
Write-Output ('Backup: ' + $backupRoot)
foreach ($name in $names) {
    $target = Join-Path $publicRoot $name
    [IO.File]::WriteAllBytes($target, $sourceBytes[$name])
    if ((Get-Acl -LiteralPath $target).Sddl -cne $beforeAcl[$name]) { throw 'ACL changed; stop without changing ACL.' }
    if ((Get-FileHash -LiteralPath $target).Hash -cne $expectedHashes[$name].Source) { throw 'Content verification failed; restore backups.' }
}
`````

バックアップディレクトリは削除せず、絶対パスと前後のSHA256を記録する。
同期直前・直後に他の配置処理を並行実行しない。途中失敗時は新規接続試験へ進まず、バックアップを保持する。

## 復元

復元も同じ2ファイルの内容変更であり、対象とバックアップを確認した明示承認の範囲でだけ実行する。
同期時の`$backupRoot`を指定し、両バックアップの存在・記録した旧SHA256・復元先の非reparseを確認してから戻す。

`````powershell
$beforeAcl = Get-Content -LiteralPath (Join-Path $backupRoot 'acl-before.json') -Raw | ConvertFrom-Json -AsHashtable
foreach ($name in $names) {
    $target = Join-Path $publicRoot $name
    $backup = Join-Path $backupRoot $name
    if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point rejected.' }
    if ((Get-FileHash -LiteralPath $backup).Hash -cne $expectedHashes[$name].Target) { throw 'Backup changed.' }
}
foreach ($name in $names) {
    $target = Join-Path $publicRoot $name
    [IO.File]::WriteAllBytes($target, [IO.File]::ReadAllBytes((Join-Path $backupRoot $name)))
    if ((Get-FileHash -LiteralPath $target).Hash -cne $expectedHashes[$name].Target) { throw 'Restore content mismatch.' }
    if ((Get-Acl -LiteralPath $target).Sddl -cne $beforeAcl[$name]) { throw 'ACL differs; stop without changing ACL.' }
}
`````

## 検証

ACL不要の回帰試験は`pwsh -NoProfile -File tests/docker-ssh-bootstrap-diagnostics.ps1`。
実bootstrapを一時ディレクトリへコピーし、deployment検証だけを合成readerに差し替える。実配置・ACL・Docker・SSH・psmuxは操作しない。
ACL fixtureと実SSH統合試験の成功を代替しない。

承認された同期の後、新しい外部SSH接続と自己SSH接続で必須bootstrapの成功を確認する。
期待値は`DOCKER_SSH_MANAGED=1`、`PSMUX_SSH_AUTOATTACH=0`、PATH先頭のDockerが選択deploymentのdispatcherであること。
既存接続や常用psmuxは操作しない。Docker認証・実操作は別の統合試験として記録する。
