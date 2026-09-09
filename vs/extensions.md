# Visual Studio 2026 拡張機能

調査対象は、次のユーザー単位の拡張機能ディレクトリです。

    %LOCALAPPDATA%\Microsoft\VisualStudio\18.0_c0228f5d\Extensions

Marketplace対応かどうかと、ユーザー単位でインストールされているかどうかは別の軸です。下表の15件はすべてこのユーザープロファイル配下にあります。バイナリはコピーしていません。

| 区分 | 拡張機能 | Version | Publisher | VSIX ID | Marketplaceまたは出所 |
| --- | --- | --- | --- | --- | --- |
| Marketplace未確認・手動/独自配置候補 | ValueChangedGenerator | 1.0 | xii-h | ValueChangedGenerator.3764d9b9-7ffa-4fb3-9680-d5ce16903661 | ローカルメタデータとMarketplace検索でURLを確認できず |
| Marketplace | Copy As Html 2022 | 17.0.4 | Microsoft DevLabs | CopyAsHtml2022.42374550-426a-400e-96f9-237682e8dea6 | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.CopyAsHtml |
| Marketplace | Parallel Builds Monitor | 1.11 | Krzysztof Buchacz | ParallelBuildsMonitor.25D5079B-D885-4D26-9472-99594F1A2EB9 | https://marketplace.visualstudio.com/items?itemName=ivson4.ParallelBuildsMonitor-18691 |
| Marketplace | VSColorOutput64 | 2023.4 | Mike Ward - Ann Arbor | 65dd734b-180a-4c67-b245-56de889637e1 | https://marketplace.visualstudio.com/items?itemName=MikeWard-AnnArbor.VSColorOutput64 |
| Marketplace | Middle Click Scroll 2022 | 17.0 | Microsoft DevLabs | MiddleClickScroll2022.263a3239-a004-40e6-b790-4fd371832c85 | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.MiddleClickScroll |
| Marketplace | Solution Error Visualizer 2022 | 17.0 | Microsoft DevLabs | SolutionErrorVisualizer2022.a392f96b-6b33-4b53-b4bb-3376a05f986c | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.SolutionErrorVisualizer |
| Marketplace | Double-Click Maximize 2022 | 17.0 | Microsoft DevLabs | DoubleClickMaximize2022.050825c2-33a4-4b7d-b3af-bd46bd99a265 | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.Double-ClickMaximize |
| Marketplace component | Productivity Power Tools Options Page 2022 | 17.0 | Microsoft DevLabs | PPTOptionsPage2022.666715a6-3ac4-4bb7-b538-4d7625f99666 | Productivity Power Tools 2022の子コンポーネント |
| Marketplace | Fix Mixed Tabs 2022 | 17.0 | Microsoft DevLabs | FixMixedTabs2022.9f1d3050-b986-4b10-ae36-97c6efc5e968 | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.FixMixedTabs |
| Marketplace | Peek Help 2022 | 17.0 | Microsoft DevLabs | PeekHelp2022.51f43c96-8220-43bf-a922-390a361e7640 | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.PeekHelp |
| Marketplace | Align Assignments 2022 | 17.0 | Microsoft DevLabs | AlignAssignments2022.41858b2d-ff0b-4a43-80b0-f1b2d6084935 | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.AlignAssignments |
| Marketplace | VsVim 2022 | 2.10.0.6 | Jared Parsons | VsVim.Microsoft.e97cd707-324b-4e35-a669-eef8dae4b8cf | https://marketplace.visualstudio.com/items?itemName=JaredParMSFT.VsVim |
| Marketplace | Shrink Empty Lines 2022 | 17.0 | Microsoft DevLabs | SyntacticLineCompression2022.4452fb8f-b348-49eb-9499-76669d3f9c75 | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.SyntacticLineCompression |
| Marketplace | Productivity Power Tools 2022 | 17.0 | Microsoft DevLabs | ProductivityPowerPack2022.0d5b9d71-e118-46de-a20c-555176e53900 | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.ProductivityPowerPack2022 |
| Marketplace | Match Margin 2022 | 17.0 | Microsoft DevLabs | MatchMargin2022.d85a25b5-f7b3-46a9-997e-a2d669dc2c93 | https://marketplace.visualstudio.com/items?itemName=VisualStudioProductTeam.MatchMargin |

自動導入する `Parallel Builds Monitor` は、Marketplaceの版固定応答と
VSIX manifest（ID、Publisher、対象範囲）を突合したうえで、次のSHA-256に固定しています。

- Version: `1.11`
- Publisher: `Krzysztof Buchacz`
- SHA-256: `0270595f377ff1100d8359e2c7b8f3fe3158796cb105254422b07e51dfb5a083`
- VerifiedOn: `2026-09-09`

## 拡張機能固有設定

拡張機能固有の設定は、再利用可能な形で取得できなかったため、今回の成果物には含めていません。

### VSColorOutput64

- 実在する設定ファイル: %APPDATA%\VSColorOutput64\vscoloroutput.json
- 内容は色分類、正規表現パターン、ビルド出力表示の設定です。
- この作業ではファイルをコピーしていません。別環境へ持ち込む前に正規表現とパスを確認してください。

### VsVim（対象外）

- 設定は既存の `~/.vim` 管理対象のため、このディレクトリでは扱いません。

### VS2026.vssettingsに含まれる拡張機能項目

CurrentSettings.vssettingsには、Text Editor_Generalカテゴリの次の項目がありました。対応する拡張機能を先にインストールしてからIDE設定をインポートしてください。

- Advanced/MiddleClickScroll = true
- HandleEscapeAlongsideVsVimOption = true

### その他

上記以外の13件について、今回の対象範囲（Visual Studio 18.0ユーザー設定ディレクトリと拡張機能ディレクトリ）では、別名のユーザー設定ファイルを確認できませんでした。拡張機能の設定がVisual Studioの設定ストアや内部レジストリに保存される場合があるため、AppData全体やバイナリをコピーせず、各拡張機能を再インストールした後に必要な項目だけIDEから再設定してください。

## 手動確認が必要なもの

- ValueChangedGeneratorの元のVSIXまたはソース。取得できないため、ファイルを推測・再生成しない。
- VSColorOutput64の設定ファイル。
- Marketplace拡張機能のバージョン差分。VS 2026でMarketplaceページから対象バージョンを確認する。
