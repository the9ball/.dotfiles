@{
    # This inventory is derived from vs/extensions.md.  Keep the Markdown file
    # as the human-readable record; this file is the executable classification.
    SchemaVersion = 2
    SourceDocument = 'extensions.md'
    VerifiedOn = '2026-09-07'
    DefaultProfile = 'VS2026'

    # The script uses the official Marketplace gallery API to resolve the
    # current version.  It never accepts a third-party mirror as a source.
    MarketplaceApiUrl = 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery'
    MarketplaceAssetType = 'Microsoft.VisualStudio.Ide.Payload'

    Profiles = @{
        VS2026 = @{
            TargetProduct = 'Visual Studio'
            TargetVersionRange = '[18.0,19.0)'
            IncludePrerelease = $false
            Extensions = @(
        @{
            Name = 'ValueChangedGenerator'
            VsixId = 'ValueChangedGenerator.3764d9b9-7ffa-4fb3-9680-d5ce16903661'
            MarketplaceId = ''
            DownloadUrl = ''
            AcquireMethod = 'ManualOnly'
            AutoInstall = $false
            Classification = 'UnknownSource'
            CurrentVersion = '1.0'
            MarketplaceTargets = ''
            Notes = 'No official Marketplace URL, official distributor, original VSIX, or source was found; do not download automatically.'
        }
        @{
            Name = 'Copy As Html 2022'
            VsixId = 'CopyAsHtml2022.42374550-426a-400e-96f9-237682e8dea6'
            MarketplaceId = 'VisualStudioPlatformTeam.CopyAsHtml'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.CopyAsHtml'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '15.0.7'
            MarketplaceTargets = '[15.0,17.0)'
            Notes = 'Available from the official Marketplace, but the current manifest ends before 17.0 and does not support VS2026.'
        }
        @{
            Name = 'Parallel Builds Monitor'
            VsixId = 'ParallelBuildsMonitor.25D5079B-D885-4D26-9472-99594F1A2EB9'
            MarketplaceId = 'ivson4.ParallelBuildsMonitor-18691'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=ivson4.ParallelBuildsMonitor-18691'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $true
            InstallScope = 'Any'
            VersionPolicy = 'LatestCompatible'
            Classification = 'Marketplace'
            CurrentVersion = '1.11'
            MarketplaceTargets = '[15.0,17.0); [17.0,19.0)'
            Notes = 'The official Marketplace API reports a current version with a [17.0,19.0) target that includes VS2026.'
        }
        @{
            Name = 'VSColorOutput64'
            VsixId = '65dd734b-180a-4c67-b245-56de889637e1'
            MarketplaceId = 'MikeWard-AnnArbor.VSColorOutput64'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=MikeWard-AnnArbor.VSColorOutput64'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '2023.4'
            MarketplaceTargets = '[17.0,18.0); [17.4,18.0)'
            Notes = 'Available from the official Marketplace, but current targets end before 18.0 (VS2022); settings are managed separately.'
        }
        @{
            Name = 'Middle Click Scroll 2022'
            VsixId = 'MiddleClickScroll2022.263a3239-a004-40e6-b790-4fd371832c85'
            MarketplaceId = 'VisualStudioPlatformTeam.MiddleClickScroll'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.MiddleClickScroll'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '15.0.6'
            MarketplaceTargets = '[15.0,17.0)'
            Notes = 'Available from the official Marketplace, but the current manifest ends before 17.0 and does not support VS2026.'
        }
        @{
            Name = 'Solution Error Visualizer 2022'
            VsixId = 'SolutionErrorVisualizer2022.a392f96b-6b33-4b53-b4bb-3376a05f986c'
            MarketplaceId = 'VisualStudioPlatformTeam.SolutionErrorVisualizer'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.SolutionErrorVisualizer'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '15.0.5'
            MarketplaceTargets = '[15.0,17.0)'
            Notes = 'Available from the official Marketplace, but the current manifest ends before 17.0 and does not support VS2026.'
        }
        @{
            Name = 'Double-Click Maximize 2022'
            VsixId = 'DoubleClickMaximize2022.050825c2-33a4-4b7d-b3af-bd46bd99a265'
            MarketplaceId = 'VisualStudioPlatformTeam.Double-ClickMaximize'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.Double-ClickMaximize'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '15.0.5'
            MarketplaceTargets = '[15.0,17.0)'
            Notes = 'Available from the official Marketplace, but the current manifest ends before 17.0 and does not support VS2026.'
        }
        @{
            Name = 'Productivity Power Tools Options Page 2022'
            VsixId = 'PPTOptionsPage2022.666715a6-3ac4-4bb7-b538-4d7625f99666'
            MarketplaceId = ''
            DownloadUrl = ''
            AcquireMethod = 'ParentComponentOnly'
            AutoInstall = $false
            Classification = 'MarketplaceComponent'
            CurrentVersion = '17.0'
            MarketplaceTargets = ''
            Notes = 'Child component of Productivity Power Tools 2022; no standalone official source was found, and the parent is not resolvable by the current API.'
        }
        @{
            Name = 'Fix Mixed Tabs 2022'
            VsixId = 'FixMixedTabs2022.9f1d3050-b986-4b10-ae36-97c6efc5e968'
            MarketplaceId = 'VisualStudioPlatformTeam.FixMixedTabs'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.FixMixedTabs'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '15.0.6'
            MarketplaceTargets = '[15.0,17.0)'
            Notes = 'Available from the official Marketplace, but the current manifest ends before 17.0 and does not support VS2026.'
        }
        @{
            Name = 'Peek Help 2022'
            VsixId = 'PeekHelp2022.51f43c96-8220-43bf-a922-390a361e7640'
            MarketplaceId = 'VisualStudioPlatformTeam.PeekHelp'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.PeekHelp'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '15.0.6'
            MarketplaceTargets = '[15.0,17.0)'
            Notes = 'Available from the official Marketplace, but the current manifest ends before 17.0 and does not support VS2026.'
        }
        @{
            Name = 'Align Assignments 2022'
            VsixId = 'AlignAssignments2022.41858b2d-ff0b-4a43-80b0-f1b2d6084935'
            MarketplaceId = 'VisualStudioPlatformTeam.AlignAssignments'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.AlignAssignments'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '15.0.5'
            MarketplaceTargets = '[15.0,17.0)'
            Notes = 'Available from the official Marketplace, but the current manifest ends before 17.0 and does not support VS2026.'
        }
        @{
            Name = 'VsVim 2022'
            VsixId = 'VsVim.Microsoft.e97cd707-324b-4e35-a669-eef8dae4b8cf'
            MarketplaceId = 'JaredParMSFT.VsVim'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=JaredParMSFT.VsVim'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '2.8.0.0'
            MarketplaceTargets = '[14.0,17.0)'
            Notes = 'The official Marketplace and source exist, but current targets stop at VS2022. Key bindings are already managed by dotfiles ~/.vim.'
        }
        @{
            Name = 'Shrink Empty Lines 2022'
            VsixId = 'SyntacticLineCompression2022.4452fb8f-b348-49eb-9499-76669d3f9c75'
            MarketplaceId = 'VisualStudioPlatformTeam.SyntacticLineCompression'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.SyntacticLineCompression'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '15.0.7'
            MarketplaceTargets = '[15.0,17.0)'
            Notes = 'Available from the official Marketplace, but the current manifest ends before 17.0 and does not support VS2026.'
        }
        @{
            Name = 'Productivity Power Tools 2022'
            VsixId = 'ProductivityPowerPack2022.0d5b9d71-e118-46de-a20c-555176e53900'
            MarketplaceId = 'VisualStudioPlatformTeam.ProductivityPowerPack2022'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.ProductivityPowerPack2022'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceUnavailable'
            CurrentVersion = ''
            MarketplaceTargets = ''
            Notes = 'The Marketplace page is retained as a record, but the official API returned no current version; VS2026 support for the pack and components is unverified.'
        }
        @{
            Name = 'Match Margin 2022'
            VsixId = 'MatchMargin2022.d85a25b5-f7b3-46a9-997e-a2d669dc2c93'
            MarketplaceId = 'VisualStudioPlatformTeam.MatchMargin'
            DownloadUrl = 'https://marketplace.visualstudio.com/items?itemName=VisualStudioPlatformTeam.MatchMargin'
            AcquireMethod = 'MarketplaceGalleryApi'
            AutoInstall = $false
            Classification = 'MarketplaceButNotVs2026'
            CurrentVersion = '15.0.7'
            MarketplaceTargets = '[15.0,17.0)'
            Notes = 'Available from the official Marketplace, but the current manifest ends before 17.0 and does not support VS2026.'
        }
            )
        }
    }
}
