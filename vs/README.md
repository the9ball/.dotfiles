# Visual Studio 2026 設定

取得日: 2026-09-07

## 取得状態

- Windows側には Visual Studio Professional 2026 (18.8.3) がインストールされています。
- Visual Studio IDE の公式 Import/Export Settings は、このWSL環境から Windows 実行ファイルを起動できず実行できませんでした。
- VS2026.vssettings は、IDEが保存した CurrentSettings.vssettings を読み取り専用で確認した代替取得物です。
- Visual Studio Installer の公式構成エクスポートも実行できなかったため、VS2026.vsconfig は作成していません。インストール済みコンポーネントから推測したJSONは含めていません。

## 個人情報の扱い

元の設定にあった Git の既定リポジトリパスだけを、次のVisual Studioマクロに置換しています。

    %vsspv_user_appdata%\source\repos

これは元の C:\Users\<username>\source\repos に対応します。インポート先で展開されない場合は、Visual Studio の Git 設定で対象ユーザーのリポジトリパスを手動設定してください。その他のIDE設定は元ファイルから変更していません。

## 別環境での再現手順

1. 対象PCに Visual Studio 2026 をインストールします。
2. IDEで公式の Import and Export Settings 機能を開き、VS2026.vssettingsをインポートします。
3. Visual Studio Installer の対象インスタンスで公式の構成エクスポート（Export configuration）を実行し、生成した .vsconfig を `vs/VS2026.vsconfig` として保存します。
4. リポジトリルートで `powershell -ExecutionPolicy Bypass -File .\vs\install-extensions.ps1 -Profile VS2026 -DryRun` を実行し、対象とスキップ理由を確認します。
5. 問題がなければ `powershell -ExecutionPolicy Bypass -File .\vs\install-extensions.ps1 -Profile VS2026` を実行します。`vswhere.exe` で検出したプロファイル対象のVSだけを対象に、`vs/extensions.psd1` の自動化対象をユーザー単位でインストールします。
   複数の対象インスタンスがある場合は、`-InstanceId <id>` で1つに絞るか、意図的に全てへ適用するときだけ `-AllInstances` を指定します。
6. 自動化対象外のMarketplace拡張機能は、対応版が公開された場合に `vs/extensions.psd1` の該当プロファイルを更新してから再確認します。
7. extensions.md に記載した VSColorOutput64 のユーザー設定は、内容を確認してから必要な場合だけ手動で配置します。VsVimは既存の `~/.vim` 管理対象です。
8. ValueChangedGenerator はMarketplaceでの出所を確認できていないため、元のVSIXまたはソースを別途確保してから手動インストールします。

`vs/extensions.md` は取得時点の記録として維持し、実行用の分類・Marketplace ID・取得方法・Visual Studio世代ごとの対象範囲は `vs/extensions.psd1` に分離しています。実行用インベントリでは `DefaultProfile` と `Profiles` が正規の設定です。

自動化対象には `InstallScope` と `VersionPolicy` を記録できます。`Any` は同じVSインスタンスのMachine/Userいずれかに同一拡張機能があればスキップし、`LatestCompatible` はMarketplaceの互換版より古い場合だけ更新を試みます。インストール済み状態の列挙に失敗した場合は安全側で停止します。状態を確認済みとみなして続行する必要がある場合だけ、明示的に `-AllowUnknownInstalledState` を指定してください。

## 対象外

拡張機能のバイナリ、ユーザープロファイルの AppData 全体、Visual Studioのレジストリ、認証情報、commit、pushはこの成果物に含めていません。
