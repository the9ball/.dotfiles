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
4. extensions.md のMarketplace拡張機能をインストールします。
5. extensions.md に記載した VSColorOutput64 のユーザー設定は、内容を確認してから必要な場合だけ手動で配置します。VsVimは既存の `~/.vim` 管理対象です。
6. ValueChangedGenerator はMarketplaceでの出所を確認できていないため、元のVSIXまたはソースを別途確保してから手動インストールします。

## 対象外

拡張機能のバイナリ、ユーザープロファイルの AppData 全体、Visual Studioのレジストリ、認証情報、commit、pushはこの成果物に含めていません。
