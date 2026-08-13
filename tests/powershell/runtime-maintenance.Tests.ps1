param([string] $TestFilter = $env:RUNTIME_MAINTENANCE_TEST_FILTER)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repositoryRoot 'tools/runtime-maintenance.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw 'runtime-maintenance.psm1 is missing'
}
$script:runtimeMaintenanceModule = Import-Module -Name $modulePath -Force -PassThru

$script:failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures.Add($Message) }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if ($Expected -ne $Actual) { $script:failures.Add("$Message Expected=[$Expected] Actual=[$Actual]") }
}

function New-FixtureRoot {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('runtime-maintenance-tests-' + [Guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

function Write-SettingsFixture {
    param([string] $Path, [System.Text.Encoding] $Encoding = [System.Text.Encoding]::UTF8)
    $fixture = @{
        outpath = 'D:\Luna-Youtube-Downloader\downloads'
        outpaths = @('D:\Luna-Youtube-Downloader\downloads', 'C:\Users\Administrator\Downloads', 'E:\keep')
        proxy = 'preserve-me'
        presets = @(
            @{ name = 'stale'; outpath = 'C:\Users\Administrator\Downloads'; outpaths = @('D:\Luna-Youtube-Downloader\old', 'E:\preset-keep'); untouched = @{ key = 'value' } },
            @{ name = 'fresh'; outpath = 'E:\fresh'; outpaths = @('E:\fresh') }
        )
        unrelated = @{ list = @(1, 2, 3); enabled = $true }
    }
    [System.IO.File]::WriteAllText($Path, ($fixture | ConvertTo-Json -Depth 10), $Encoding)
}

function Test-RepairSettingsPreservesUnrelatedValues {
    $root = New-FixtureRoot
    try {
        $settings = Join-Path $root 'settings.json'
        $downloads = Join-Path $root 'Downloads'
        [System.IO.Directory]::CreateDirectory($downloads) | Out-Null
        Write-SettingsFixture $settings

        $result = RepairSettings -SettingsPath $settings -DownloadsPath $downloads -Confirm:$false
        $after = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json

        Assert-True $result.Changed 'RepairSettings should report a change.'
        Assert-Equal $downloads $after.outpath 'The root outpath should be repaired.'
        Assert-Equal $downloads $after.outpaths[0] 'The resolved Downloads path should lead outpaths.'
        Assert-Equal 'E:\keep' $after.outpaths[1] 'A non-stale root outpath should remain.'
        Assert-Equal 'preserve-me' $after.proxy 'Unrelated root settings must survive.'
        Assert-Equal 'value' $after.presets[0].untouched.key 'Unrelated preset settings must survive.'
        Assert-Equal $downloads $after.presets[0].outpath 'Stale preset outpath should be repaired.'
        Assert-Equal 'E:\preset-keep' $after.presets[0].outpaths[1] 'A non-stale preset outpath should remain.'
        Assert-Equal 1 @($after.presets[1].outpaths).Count 'Fresh preset outpaths must not gain a Downloads entry.'
        Assert-Equal 'E:\fresh' $after.presets[1].outpaths[0] 'Fresh preset outpaths must remain exactly unchanged.'
        Assert-True (Test-Path -LiteralPath $result.BackupPath) 'A settings backup should exist before replacement.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-RepairSettingsPreservesValidJsonBomAndNoBom {
    $root = New-FixtureRoot
    try {
        $downloads = Join-Path $root 'Downloads'
        [System.IO.Directory]::CreateDirectory($downloads) | Out-Null
        $cases = @(
            @{ Name = 'utf8-bom'; Encoding = (New-Object System.Text.UTF8Encoding($true)); Preamble = @(0xEF, 0xBB, 0xBF) },
            @{ Name = 'utf8-no-bom'; Encoding = (New-Object System.Text.UTF8Encoding($false)); Preamble = @() }
        )
        foreach ($case in $cases) {
            $settings = Join-Path $root ($case.Name + '.json')
            Write-SettingsFixture $settings $case.Encoding
            RepairSettings -SettingsPath $settings -DownloadsPath $downloads -Confirm:$false | Out-Null
            $bytes = [System.IO.File]::ReadAllBytes($settings)
            if ($case.Preamble.Count -eq 0) {
                Assert-Equal 0x7B $bytes[0] "$($case.Name) must remain free of a BOM."
            }
            else {
                Assert-Equal ([Convert]::ToBase64String([byte[]]$case.Preamble)) ([Convert]::ToBase64String($bytes[0..($case.Preamble.Count - 1)])) "$($case.Name) must preserve its BOM state."
            }
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-RepairSettingsLeavesMalformedInputUntouched {
    $root = New-FixtureRoot
    try {
        $settings = Join-Path $root 'settings.json'
        [System.IO.File]::WriteAllText($settings, '{ malformed', [System.Text.Encoding]::UTF8)
        $before = [System.IO.File]::ReadAllBytes($settings)
        try { RepairSettings -SettingsPath $settings -DownloadsPath (Join-Path $root 'Downloads') -Confirm:$false | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'Malformed settings must block repair.'
        Assert-Equal ([Convert]::ToBase64String($before)) ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($settings))) 'Malformed settings must remain byte-for-byte untouched.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-RepairSettingsWhatIfDoesNotReplace {
    $root = New-FixtureRoot
    try {
        $settings = Join-Path $root 'settings.json'
        Write-SettingsFixture $settings
        $before = [System.IO.File]::ReadAllBytes($settings)
        RepairSettings -SettingsPath $settings -DownloadsPath (Join-Path $root 'Downloads') -WhatIf | Out-Null
        Assert-Equal ([Convert]::ToBase64String($before)) ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($settings))) 'WhatIf must not replace settings.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function New-VersionReader {
    param([string] $ExpectedVersion)
    return { param([string] $Path) $ExpectedVersion }.GetNewClosure()
}

function New-ContentVersionReader {
    param([hashtable] $Versions)
    return {
        param([string] $Path)
        $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::ASCII)
        return $Versions[$content]
    }.GetNewClosure()
}

function New-PriorProvenanceBytes {
    param([string] $Version, [string] $Sha256)
    $value = [ordered]@{ repository = 'yt-dlp/yt-dlp-nightly-builds'; channel = 'nightly'; tag = $Version; asset = 'yt-dlp.exe'; sha256 = $Sha256 }
    return [Text.UTF8Encoding]::new($false).GetBytes(($value | ConvertTo-Json))
}

function Invoke-FixtureYtDlpTransaction {
    param(
        [string] $TargetPath,
        [string] $AssetPath,
        [string] $ReleaseTag,
        [string] $ExpectedSha256,
        [scriptblock] $VersionReader,
        [switch] $SimulatePostReplaceFailure,
        [switch] $WhatIf,
        [scriptblock] $ProvenanceWriter,
        [scriptblock] $PreimageRestorer
    )
    $module = $script:runtimeMaintenanceModule
    & $module {
        param($TargetPath, $AssetPath, $ReleaseTag, $ExpectedSha256, $VersionReader, $SimulatePostReplaceFailure, $WhatIf, $ProvenanceWriter, $PreimageRestorer)
        $originalWriter = ${function:Write-ProvenanceAtomically}
        $originalRestorer = ${function:Restore-FilePreimage}
        try {
            if ($null -ne $ProvenanceWriter) {
                Set-Item -Path Function:Write-ProvenanceAtomically -Value $ProvenanceWriter
            }
            if ($null -ne $PreimageRestorer) { Set-Item -Path Function:Restore-FilePreimage -Value $PreimageRestorer }
            Invoke-YtDlpTransaction -TargetPath $TargetPath -AssetPath $AssetPath -ReleaseTag $ReleaseTag -ExpectedSha256 $ExpectedSha256 -VersionReader $VersionReader -SimulatePostReplaceFailure:$SimulatePostReplaceFailure -WhatIf:$WhatIf -Confirm:$false
        }
        finally {
            if ($null -eq $originalWriter) { Remove-Item -Path Function:Write-ProvenanceAtomically -ErrorAction SilentlyContinue }
            else { Set-Item -Path Function:Write-ProvenanceAtomically -Value $originalWriter }
            Set-Item -Path Function:Restore-FilePreimage -Value $originalRestorer
        }
    } $TargetPath $AssetPath $ReleaseTag $ExpectedSha256 $VersionReader $SimulatePostReplaceFailure $WhatIf $ProvenanceWriter $PreimageRestorer
}

function Test-RuntimeMaintenanceModuleExportsOnlyPublicCommands {
    $exported = (@($script:runtimeMaintenanceModule.ExportedFunctions.Keys | Sort-Object) -join ',')
    Assert-Equal 'RepairSettings,UpdateYtDlp' $exported 'The module must export exactly the two public maintenance commands.'
    Assert-True ($null -eq (Get-Command -Name Invoke-YtDlpTransaction -ErrorAction SilentlyContinue)) 'The transaction core must not be callable from the importer scope.'
}

function Test-UpdateYtDlpRejectsCallerControlledSeams {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        $parameters = (Get-Command UpdateYtDlp).Parameters
        Assert-True (-not $parameters.ContainsKey('AssetPath')) 'Public UpdateYtDlp must not expose an asset override.'
        Assert-True (-not $parameters.ContainsKey('ExpectedSha256')) 'Public UpdateYtDlp must not expose a checksum override.'
        Assert-True (-not $parameters.ContainsKey('ReleaseTag')) 'Public UpdateYtDlp must not expose a release-tag override.'
        Assert-True (-not $parameters.ContainsKey('VersionReader')) 'Public UpdateYtDlp must not expose a version-reader override.'
        try { UpdateYtDlp -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'test-tag') -WhatIf | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'Public UpdateYtDlp must reject caller-controlled download and verification seams.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'Rejected public seams must retain the target.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-UpdateYtDlpDeclinedConfirmDoesNotReplace {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        $childScript = Join-Path $root 'declined-confirm.ps1'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $child = @"
`$ErrorActionPreference = 'Stop'
`$module = Import-Module -Name '$modulePath' -Force -PassThru
& `$module {
    param(`$TargetPath, `$AssetPath)
    function Get-OfficialNightlyAsset {
        param([string] `$StagingPath)
        return [pscustomobject]@{ AssetPath = `$AssetPath; ReleaseTag = 'fixture-tag'; ExpectedSha256 = (Get-FileHash -LiteralPath `$AssetPath -Algorithm SHA256).Hash }
    }
    function Get-YtDlpVersion { param([string] `$Path, [scriptblock] `$VersionReader) return 'fixture-tag' }
    `$result = UpdateYtDlp -TargetPath `$TargetPath -Confirm
    Write-Output ('DECLINED=' + [bool]`$result.Declined)
} '$target' '$asset'
"@
        [IO.File]::WriteAllText($childScript, $child, [Text.Encoding]::UTF8)
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = (Join-Path $PSHOME 'powershell.exe')
        $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$childScript`""
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($startInfo)
        $process.StandardInput.WriteLine('N')
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        Assert-Equal 0 $process.ExitCode "A declined public confirmation should complete without a transaction error. Output=$output"
        Assert-True ($output -match 'DECLINED=True') 'A declined public confirmation must report Declined.'
        Assert-Equal 'old-binary' ([IO.File]::ReadAllText($target)) 'A declined public confirmation must not replace the target.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-UpdateYtDlpWhatIfVerifiesWithoutReplacing {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [IO.File]::WriteAllText($target, 'old-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($asset, 'new-binary', [Text.Encoding]::ASCII)
        $module = $script:runtimeMaintenanceModule
        $verification = & $module {
            param($TargetPath, $AssetPath)
            $script:fixtureVersionCalls = 0
            function Get-OfficialNightlyAsset {
                param([string] $StagingPath)
                return [pscustomobject]@{ AssetPath = $AssetPath; ReleaseTag = 'fixture-tag'; ExpectedSha256 = (Get-FileHash -LiteralPath $AssetPath -Algorithm SHA256).Hash }
            }
            function Get-YtDlpVersion { param([string] $Path, [scriptblock] $VersionReader) $script:fixtureVersionCalls++; return 'fixture-tag' }
            $result = UpdateYtDlp -TargetPath $TargetPath -WhatIf
            return [pscustomobject]@{ Updated = $result.Updated; VersionCalls = $script:fixtureVersionCalls }
        } $target $asset
        Assert-True (-not $verification.Updated) 'Public WhatIf must not replace the target.'
        Assert-True ($verification.VersionCalls -gt 0) 'Public WhatIf must still verify the staged asset version.'
        Assert-Equal 'old-binary' ([IO.File]::ReadAllText($target)) 'Public WhatIf must retain the target.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionBlocksHashMismatch {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        try { Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 ('0' * 64) -VersionReader (New-VersionReader 'test-tag') | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'A hash mismatch must block replacement.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'A hash mismatch must retain the target.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionBlocksVersionMismatch {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        try { Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'expected-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'wrong-tag') | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'A staged version mismatch must block replacement.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'A version mismatch must retain the target.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionRejectsNonCanonicalTarget {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'not-ytdlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        try { Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'test-tag') | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'The transaction must reject an arbitrary target leaf.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'A rejected target must remain unchanged.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionRejectsTraversalTarget {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $nested = Join-Path $root 'nested'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.Directory]::CreateDirectory($nested) | Out-Null
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        $traversalTarget = Join-Path $nested '..\yt-dlp.exe'
        try { Invoke-FixtureYtDlpTransaction -TargetPath $traversalTarget -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'test-tag') | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'The transaction must reject a traversal target path.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'A traversal target must remain unchanged.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionWritesCanonicalSiblingProvenance {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash

        $result = Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'test-tag')
        $manifest = Get-Content -LiteralPath $provenance -Raw | ConvertFrom-Json

        Assert-True $result.Updated 'Verified asset should replace the target.'
        Assert-Equal 'new-binary' ([System.IO.File]::ReadAllText($target)) 'The verified asset should be deployed.'
        Assert-Equal 'yt-dlp/yt-dlp-nightly-builds' $manifest.repository 'Provenance must identify the official repository.'
        Assert-Equal $hash $manifest.sha256 'Provenance must record the verified hash.'
        Assert-True (Test-Path -LiteralPath $result.BackupPath) 'The previous target must be retained as a backup.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionRecordsPreviousVersionInProvenance {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        $versions = @{ 'old-binary' = 'previous-tag'; 'new-binary' = 'test-tag' }

        Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-ContentVersionReader $versions) | Out-Null
        $manifest = Get-Content -LiteralPath $provenance -Raw | ConvertFrom-Json

        Assert-Equal 'previous-tag' $manifest.previousVersion 'Provenance must record the version observed before replacement.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionRestoresProvenanceAfterCommitFailure {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($provenance, '{"old":"provenance"}', [System.Text.Encoding]::UTF8)
        $oldProvenance = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($provenance))
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        $versions = @{ 'old-binary' = 'previous-tag'; 'new-binary' = 'test-tag' }
        $writerMarker = Join-Path $root 'provenance-writer-called'
        $writer = {
            param($Path, $Manifest)
            [System.IO.File]::WriteAllText($writerMarker, 'called', [System.Text.Encoding]::ASCII)
            throw 'simulated_provenance_commit_failure'
        }.GetNewClosure()

        try { Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-ContentVersionReader $versions) -ProvenanceWriter $writer | Out-Null; $threw = $false } catch { $threw = $true }

        Assert-True $threw 'A provenance commit failure must be reported.'
        Assert-True (Test-Path -LiteralPath $writerMarker) 'The transaction must use the atomic provenance writer.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'A provenance commit failure must restore the prior executable.'
        Assert-Equal $oldProvenance ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($provenance))) 'A provenance commit failure must restore the prior provenance bytes.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionRecoversInterruptedReplacementFromJournal {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($backup, 'old-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $oldProvenance = New-PriorProvenanceBytes -Version 'previous-tag' -Sha256 (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
        $record = [ordered]@{
            schemaVersion = 1
            targetPath = $target
            backupPath = $backup
            previousSha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToUpperInvariant()
            previousVersion = 'previous-tag'
            provenanceExisted = $true
            provenanceBytesBase64 = [Convert]::ToBase64String($oldProvenance)
        }
        [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        $module = $script:runtimeMaintenanceModule
        & $module { param($TargetPath, $VersionReader) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader $VersionReader } $target (New-ContentVersionReader @{ 'old-binary' = 'previous-tag'; 'new-binary' = 'test-tag' })
        Assert-Equal 'old-binary' ([IO.File]::ReadAllText($target)) 'A residual journal must restore the pre-replacement executable.'
        Assert-Equal ([Convert]::ToBase64String($oldProvenance)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))) 'A residual journal must restore the exact provenance preimage.'
        Assert-True (-not (Test-Path -LiteralPath $journal)) 'A verified recovery must delete the residual journal.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionRejectsCorruptJournalBackupBeforeOverwrite {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($backup, 'corrupt-binary', [Text.Encoding]::ASCII)
        $expectedPrevious = [Text.Encoding]::ASCII.GetBytes('old-binary')
        $record = [ordered]@{ schemaVersion = 1; targetPath = $target; backupPath = $backup; previousSha256 = ([Security.Cryptography.SHA256]::Create().ComputeHash($expectedPrevious) | ForEach-Object { $_.ToString('X2') }) -join ''; previousVersion = 'previous-tag'; provenanceExisted = $false; provenanceBytesBase64 = '' }
        [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        $module = $script:runtimeMaintenanceModule
        try { & $module { param($TargetPath) Restore-PendingYtDlpTransaction -TargetPath $TargetPath } $target; $threw = $false } catch { $threw = $_.Exception.Message -eq 'The pending yt-dlp transaction backup does not match its prior hash.' }
        Assert-True $threw 'A corrupt journal backup must be rejected before recovery overwrites the target.'
        Assert-Equal 'new-binary' ([IO.File]::ReadAllText($target)) 'A corrupt journal backup must not overwrite the current target.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-UpdateYtDlpRecoversPendingTransactionBeforeMetadataFetch {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        $journal = Join-Path $root 'yt-dlp-transaction.json'
        $realYtDlp = (Resolve-Path -LiteralPath (Join-Path $repositoryRoot '..\yt-dlp.exe')).Path
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
        [IO.File]::Copy($realYtDlp, $backup)
        [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $previousExecutableSha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
        $previousVersion = (& $realYtDlp --version | Out-String).Trim()
        $previousProvenanceBytes = New-PriorProvenanceBytes -Version $previousVersion -Sha256 $previousExecutableSha256
        $record = [ordered]@{
            schemaVersion = 1
            targetPath = $target
            backupPath = $backup
            previousSha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToUpperInvariant()
            previousVersion = $previousVersion
            provenanceExisted = $true
            provenanceBytesBase64 = [Convert]::ToBase64String($previousProvenanceBytes)
        }
        [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        $module = $script:runtimeMaintenanceModule
        & $module { function script:Get-OfficialNightlyAsset { param([string] $StagingPath) throw 'simulated_metadata_fetch_failure' } }
        $failure = & $module {
            param($TargetPath)
            try { UpdateYtDlp -TargetPath $TargetPath -Confirm:$false | Out-Null; return $null }
            catch { return $_.Exception.Message }
        } $target

        Assert-Equal 'simulated_metadata_fetch_failure' $failure 'The public update fixture must stop at the metadata fetch boundary.'
        Assert-Equal $previousExecutableSha256 (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash 'A public update must recover the pending executable before metadata fetch begins.'
        Assert-Equal ([Convert]::ToBase64String($previousProvenanceBytes)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))) 'A public update must recover the pending provenance before metadata fetch begins.'
        Assert-True (-not (Test-Path -LiteralPath $journal)) 'A public update must finish verified pending recovery before metadata fetch begins.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRecoveryRejectsPreviousVersionMismatchBeforeMutation {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($backup, 'old-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $targetBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($target))
        $provenanceBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))
        $record = [ordered]@{
            schemaVersion = 1
            targetPath = $target
            backupPath = $backup
            previousSha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToUpperInvariant()
            previousVersion = 'journal-claims-a-different-version'
            provenanceExisted = $true
            provenanceBytesBase64 = [Convert]::ToBase64String((New-PriorProvenanceBytes -Version 'actual-backup-version' -Sha256 (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash))
        }
        [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        $module = $script:runtimeMaintenanceModule
        try {
            & $module { param($TargetPath, $VersionReader) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader $VersionReader } $target (New-ContentVersionReader @{ 'old-binary' = 'actual-backup-version'; 'new-binary' = 'new-version' })
            $threw = $false
        }
        catch { $threw = $true }

        Assert-True $threw 'A previousVersion mismatch must reject pending recovery.'
        Assert-Equal $targetBefore ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target))) 'A previousVersion mismatch must be rejected before the executable is mutated.'
        Assert-Equal $provenanceBefore ([Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))) 'A previousVersion mismatch must be rejected before provenance is mutated.'
        Assert-True (Test-Path -LiteralPath $journal) 'A rejected previousVersion mismatch must retain its journal for diagnosis.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRecoveryRejectsMalformedProvenanceBase64BeforeMutation {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($backup, 'old-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $targetBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($target))
        $provenanceBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))
        $record = [ordered]@{
            schemaVersion = 1
            targetPath = $target
            backupPath = $backup
            previousSha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToUpperInvariant()
            previousVersion = 'previous-tag'
            provenanceExisted = $true
            provenanceBytesBase64 = 'not-valid-base64!'
        }
        [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        $module = $script:runtimeMaintenanceModule
        try {
            & $module { param($TargetPath, $VersionReader) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader $VersionReader } $target (New-ContentVersionReader @{ 'old-binary' = 'previous-tag'; 'new-binary' = 'new-tag' })
            $threw = $false
        }
        catch { $threw = $true }

        Assert-True $threw 'Malformed provenance base64 must reject pending recovery.'
        Assert-Equal $targetBefore ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target))) 'Malformed provenance base64 must be rejected before the executable is mutated.'
        Assert-Equal $provenanceBefore ([Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))) 'Malformed provenance base64 must be rejected before provenance is mutated.'
        Assert-True (Test-Path -LiteralPath $journal) 'Malformed provenance base64 must retain its journal for diagnosis.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionWhatIfDoesNotRecoverPendingJournal {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $asset = Join-Path $root 'asset.exe'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($backup, 'old-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($asset, 'candidate-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $targetBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($target))
        $provenanceBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))
        $record = [ordered]@{
            schemaVersion = 1
            targetPath = $target
            backupPath = $backup
            previousSha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToUpperInvariant()
            previousVersion = 'fixture-tag'
            provenanceExisted = $true
            provenanceBytesBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"old":"provenance"}'))
        }
        [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash

        Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'fixture-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'fixture-tag') -WhatIf | Out-Null

        Assert-Equal $targetBefore ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target))) 'WhatIf must not recover a pending executable journal.'
        Assert-Equal $provenanceBefore ([Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))) 'WhatIf must not restore pending provenance bytes.'
        Assert-True (Test-Path -LiteralPath $journal) 'WhatIf must not delete a pending transaction journal.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRecoveryRejectsUntrustedBackupPathsBeforeExecution {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $targetBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($target))
        $provenanceBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))
        $outside = Join-Path ([IO.Path]::GetTempPath()) ('yt-dlp.exe.backup-20260813120000.' + [Guid]::NewGuid().ToString('N'))
        $cases = @(
            @{ Name = 'outside sibling directory'; Path = $outside; Create = $true },
            @{ Name = 'relative path'; Path = 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; Create = $true },
            @{ Name = 'alternate data stream'; Path = ($target + ':rollback'); Create = $false },
            @{ Name = 'wrong prefix'; Path = (Join-Path $root 'other.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'); Create = $true }
        )
        foreach ($case in $cases) {
            [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
            [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
            if ($case.Create) { [IO.File]::WriteAllText($case.Path, 'old-binary', [Text.Encoding]::ASCII) }
            $oldHash = ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes('old-binary')) | ForEach-Object { $_.ToString('X2') }) -join ''
            $record = [ordered]@{ schemaVersion = 1; targetPath = $target; backupPath = $case.Path; previousSha256 = $oldHash; previousVersion = 'previous-tag'; provenanceExisted = $true; provenanceBytesBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"old":"provenance"}')) }
            [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
            $module = $script:runtimeMaintenanceModule
            try { & $module { param($TargetPath) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader { 'previous-tag' } } $target; $threw = $false } catch { $threw = $true }
            Assert-True $threw "An untrusted $($case.Name) backupPath must be rejected."
            Assert-Equal $targetBefore ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target))) "An untrusted $($case.Name) backupPath must be rejected before executable mutation."
            Assert-Equal $provenanceBefore ([Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))) "An untrusted $($case.Name) backupPath must be rejected before provenance mutation."
            Assert-True (Test-Path -LiteralPath $journal) "An untrusted $($case.Name) backupPath must retain the journal."
            Remove-Item -LiteralPath $case.Path -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        if ($null -ne $outside) { Remove-Item -LiteralPath $outside -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-YtDlpRecoveryRequiresTypedJournalSchemaAndEmptyAbsentPreimage {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $provenance = Join-Path $root 'yt-dlp-provenance.json'
        $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($backup, 'old-binary', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $valid = [ordered]@{ schemaVersion = 1; targetPath = $target; backupPath = $backup; previousSha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash; previousVersion = 'previous-tag'; provenanceExisted = $false; provenanceBytesBase64 = '' }
        $cases = @(
            @{ Name = 'missing previousVersion'; Mutate = { param($r) $r.Remove('previousVersion') } },
            @{ Name = 'string schemaVersion'; Mutate = { param($r) $r.schemaVersion = '1' } },
            @{ Name = 'string provenanceExisted'; Mutate = { param($r) $r.provenanceExisted = 'false' } },
            @{ Name = 'nonempty absent preimage'; Mutate = { param($r) $r.provenanceBytesBase64 = [Convert]::ToBase64String([byte[]](1)) } }
        )
        foreach ($case in $cases) {
            [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII)
            [IO.File]::WriteAllText($backup, 'old-binary', [Text.Encoding]::ASCII)
            [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
            $record = [ordered]@{}; foreach ($key in $valid.Keys) { $record[$key] = $valid[$key] }; & $case.Mutate $record
            [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
            $module = $script:runtimeMaintenanceModule
            try { & $module { param($TargetPath) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader { 'previous-tag' } } $target; $threw = $false } catch { $threw = $true }
            Assert-True $threw "A journal with $($case.Name) must be rejected."
            Assert-Equal 'new-binary' ([IO.File]::ReadAllText($target)) "A journal with $($case.Name) must be rejected before executable mutation."
            $provenanceAfter = if (Test-Path -LiteralPath $provenance -PathType Leaf) { [IO.File]::ReadAllText($provenance) } else { '<missing>' }
            Assert-Equal '{"new":"provenance"}' $provenanceAfter "A journal with $($case.Name) must be rejected before provenance mutation."
            Assert-True (Test-Path -LiteralPath $journal) "A journal with $($case.Name) must be retained."
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRecoveryRetainsJournalWhenProvenanceVerificationFails {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'; $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; $provenance = Join-Path $root 'yt-dlp-provenance.json'; $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII); [IO.File]::WriteAllText($backup, 'old-binary', [Text.Encoding]::ASCII); [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $previousBytes = New-PriorProvenanceBytes -Version 'previous-tag' -Sha256 (Get-FileHash $backup -Algorithm SHA256).Hash
        $record = [ordered]@{ schemaVersion = 1; targetPath = $target; backupPath = $backup; previousSha256 = (Get-FileHash $backup -Algorithm SHA256).Hash; previousVersion = 'previous-tag'; provenanceExisted = $true; provenanceBytesBase64 = [Convert]::ToBase64String($previousBytes) }
        [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false)); $module = $script:runtimeMaintenanceModule
        try {
            & $module {
                param($TargetPath)
                $originalRestorer = ${function:script:Restore-FilePreimage}
                try {
                    function script:Restore-FilePreimage { param($Path,$Bytes,$Existed) }
                    Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader { 'previous-tag' }
                }
                finally { Set-Item Function:script:Restore-FilePreimage $originalRestorer }
            } $target
            $threw = $false
        }
        catch { $threw = $true }
        Assert-True $threw 'Recovery must report provenance restoration verification failure.'
        Assert-Equal '{"new":"provenance"}' ([IO.File]::ReadAllText($provenance)) 'The injection must leave the wrong provenance observable.'
        Assert-True (Test-Path $journal) 'Recovery must retain its journal when provenance verification fails.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRollbackRetainsJournalWhenProvenanceVerificationFails {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'; $asset = Join-Path $root 'asset.exe'; $provenance = Join-Path $root 'yt-dlp-provenance.json'; $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'old-binary', [Text.Encoding]::ASCII); [IO.File]::WriteAllText($asset, 'new-binary', [Text.Encoding]::ASCII); [IO.File]::WriteAllText($provenance, '{"old":"provenance"}', [Text.Encoding]::UTF8)
        $hash = (Get-FileHash $asset -Algorithm SHA256).Hash; $versions = @{ 'old-binary'='previous-tag'; 'new-binary'='test-tag' }
        try { Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-ContentVersionReader $versions) -SimulatePostReplaceFailure -PreimageRestorer { param($Path,$Bytes,$Existed) [IO.File]::WriteAllText($Path, '{"wrong":"provenance"}', [Text.Encoding]::UTF8) } | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'Rollback must report provenance restoration verification failure.'
        Assert-Equal '{"wrong":"provenance"}' ([IO.File]::ReadAllText($provenance)) 'The rollback injection must leave wrong provenance observable.'
        Assert-True (Test-Path $journal) 'Rollback must retain its journal when provenance verification fails.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRecoveryHandlesPreReplaceJournal {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'; $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; $provenance = Join-Path $root 'yt-dlp-provenance.json'; $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'old-binary', [Text.Encoding]::ASCII); $previousBytes=New-PriorProvenanceBytes -Version 'previous-tag' -Sha256 (Get-FileHash $target -Algorithm SHA256).Hash; [IO.File]::WriteAllBytes($provenance,$previousBytes)
        $record = [ordered]@{ schemaVersion = 1; targetPath = $target; backupPath = $backup; previousSha256 = (Get-FileHash $target -Algorithm SHA256).Hash; previousVersion = 'previous-tag'; provenanceExisted = $true; provenanceBytesBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance)) }
        [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false)); $module=$script:runtimeMaintenanceModule
        & $module { param($TargetPath) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader { 'previous-tag' } } $target
        Assert-Equal 'old-binary' ([IO.File]::ReadAllText($target)) 'A pre-replace journal must retain the prior executable.'; Assert-True (-not (Test-Path $journal)) 'A verified pre-replace journal must be cleared.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRecoveryRejectsMissingBackupWithoutMutation {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'; $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; $provenance = Join-Path $root 'yt-dlp-provenance.json'; $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII); [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $oldHash = ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes('old-binary')) | ForEach-Object { $_.ToString('X2') }) -join ''
        $record = [ordered]@{ schemaVersion = 1; targetPath = $target; backupPath = $backup; previousSha256 = $oldHash; previousVersion = 'previous-tag'; provenanceExisted = $false; provenanceBytesBase64 = '' }
        [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false)); $module=$script:runtimeMaintenanceModule
        try { & $module { param($TargetPath) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader { 'new-tag' } } $target; $threw=$false } catch { $threw=$true }
        Assert-True $threw 'A missing backup with a non-prior target must be rejected.'; Assert-Equal 'new-binary' ([IO.File]::ReadAllText($target)) 'Missing-backup rejection must not mutate executable.'; Assert-Equal '{"new":"provenance"}' ([IO.File]::ReadAllText($provenance)) 'Missing-backup rejection must not mutate provenance.'; Assert-True (Test-Path $journal) 'Missing-backup rejection must retain journal.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRecoveryReplayIsIdempotent {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'; $backup = Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; $provenance = Join-Path $root 'yt-dlp-provenance.json'; $journal = Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target, 'new-binary', [Text.Encoding]::ASCII); [IO.File]::WriteAllText($backup, 'old-binary', [Text.Encoding]::ASCII); [IO.File]::WriteAllText($provenance, '{"new":"provenance"}', [Text.Encoding]::UTF8)
        $previousBytes=New-PriorProvenanceBytes -Version 'previous-tag' -Sha256 (Get-FileHash $backup -Algorithm SHA256).Hash
        $record=[ordered]@{schemaVersion=1;targetPath=$target;backupPath=$backup;previousSha256=(Get-FileHash $backup -Algorithm SHA256).Hash;previousVersion='previous-tag';provenanceExisted=$true;provenanceBytesBase64=[Convert]::ToBase64String($previousBytes)}
        [IO.File]::WriteAllText($journal,($record|ConvertTo-Json),[Text.UTF8Encoding]::new($false)); $module=$script:runtimeMaintenanceModule
        & $module { param($TargetPath) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader { 'previous-tag' }; Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader { 'previous-tag' } } $target
        Assert-Equal 'old-binary' ([IO.File]::ReadAllText($target)) 'Replayed recovery must retain recovered executable.'; Assert-Equal ([Convert]::ToBase64String($previousBytes)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($provenance))) 'Replayed recovery must retain recovered provenance.'; Assert-True (-not (Test-Path $journal)) 'Replayed recovery must leave no journal.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRecoveryRejectsSelfDeclaredBackupIdentity {
    $root = New-FixtureRoot
    try {
        $target=Join-Path $root 'yt-dlp.exe'; $backup=Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; $provenance=Join-Path $root 'yt-dlp-provenance.json'; $journal=Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target,'new-binary',[Text.Encoding]::ASCII); [IO.File]::WriteAllText($backup,'attacker-binary',[Text.Encoding]::ASCII); [IO.File]::WriteAllText($provenance,'{"current":"provenance"}',[Text.Encoding]::UTF8)
        $attackerHash=(Get-FileHash $backup -Algorithm SHA256).Hash
        $trustedBytes=New-PriorProvenanceBytes -Version 'trusted-tag' -Sha256 ('A' * 64)
        $record=[ordered]@{schemaVersion=1;targetPath=$target;backupPath=$backup;previousSha256=$attackerHash;previousVersion='attacker-tag';provenanceExisted=$true;provenanceBytesBase64=[Convert]::ToBase64String($trustedBytes)}
        [IO.File]::WriteAllText($journal,($record|ConvertTo-Json),[Text.UTF8Encoding]::new($false)); $module=$script:runtimeMaintenanceModule
        try { & $module { param($TargetPath) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader { 'attacker-tag' } } $target; $threw=$false } catch { $threw=$true }
        Assert-True $threw 'Recovery must reject backup identity that conflicts with decoded prior provenance.'
        Assert-Equal 'new-binary' ([IO.File]::ReadAllText($target)) 'A self-declared backup identity must be rejected before execution or restore.'
        Assert-True (Test-Path $journal) 'A rejected self-declared identity must retain its journal.'
    }
    finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-UpdateYtDlpRejectsElevatedExecutionBeforeRecovery {
    $root=New-FixtureRoot
    try {
        $target=Join-Path $root 'yt-dlp.exe'; [IO.File]::WriteAllText($target,'old-binary',[Text.Encoding]::ASCII); $module=$script:runtimeMaintenanceModule
        $message = & $module {
            param($TargetPath)
            $originalElevation = ${function:script:Test-IsElevated}; $originalMetadata = ${function:script:Get-OfficialNightlyAsset}
            try {
                function script:Test-IsElevated { return $true }; function script:Get-OfficialNightlyAsset { throw 'metadata_must_not_run' }
                try { UpdateYtDlp -TargetPath $TargetPath -Confirm:$false | Out-Null; return $null } catch { return $_.Exception.Message }
            }
            finally { Set-Item Function:script:Test-IsElevated $originalElevation; Set-Item Function:script:Get-OfficialNightlyAsset $originalMetadata }
        } $target
        Assert-Equal 'UpdateYtDlp must be run from an unelevated PowerShell process.' $message 'Public update must reject elevated execution before recovery or metadata work.'
        Assert-Equal 'old-binary' ([IO.File]::ReadAllText($target)) 'Elevated rejection must not mutate the executable.'
    }
    finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRecoveryKeepsSnapshotWriteLockedThroughRestore {
    $root=New-FixtureRoot
    try {
        $target=Join-Path $root 'yt-dlp.exe'; $backup=Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; $journal=Join-Path $root 'yt-dlp-transaction.json'
        [IO.File]::WriteAllText($target,'new-binary',[Text.Encoding]::ASCII); [IO.File]::WriteAllText($backup,'old-binary',[Text.Encoding]::ASCII); $hash=(Get-FileHash $backup -Algorithm SHA256).Hash
        $record=[ordered]@{schemaVersion=1;targetPath=$target;backupPath=$backup;previousSha256=$hash;previousVersion='previous-tag';provenanceExisted=$false;provenanceBytesBase64=''}; [IO.File]::WriteAllText($journal,($record|ConvertTo-Json),[Text.UTF8Encoding]::new($false)); $module=$script:runtimeMaintenanceModule
        $writeSucceeded=$false
        & $module { param($TargetPath,[ref]$WriteSucceeded) Restore-PendingYtDlpTransaction -TargetPath $TargetPath -VersionReader { param($Path) if ((Split-Path -Leaf $Path) -like 'yt-dlp.recovery-snapshot.*.exe') { try { [IO.File]::WriteAllText($Path,'attacker-binary',[Text.Encoding]::ASCII); $WriteSucceeded.Value=$true } catch {} }; return 'previous-tag' }.GetNewClosure() } $target ([ref]$writeSucceeded)
        Assert-True (-not $writeSucceeded) 'The exact snapshot used for version execution must remain non-writable through restore.'
        Assert-Equal 'old-binary' ([IO.File]::ReadAllText($target)) 'Recovery must restore the same locked snapshot bytes.'
    }
    finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpSuccessRejectsWrongProvenanceBeforeJournalDelete {
    $root=New-FixtureRoot
    try {
        $target=Join-Path $root 'yt-dlp.exe'; $asset=Join-Path $root 'asset.exe'; $journal=Join-Path $root 'yt-dlp-transaction.json'; [IO.File]::WriteAllText($target,'old-binary',[Text.Encoding]::ASCII); [IO.File]::WriteAllText($asset,'new-binary',[Text.Encoding]::ASCII); $hash=(Get-FileHash $asset -Algorithm SHA256).Hash
        $writer={param($Path,$Manifest) [IO.File]::WriteAllText($Path,'{"wrong":true}',[Text.UTF8Encoding]::new($false))}
        try { Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-ContentVersionReader @{'old-binary'='previous-tag';'new-binary'='test-tag'}) -ProvenanceWriter $writer | Out-Null; $threw=$false } catch {$threw=$true}
        Assert-True $threw 'Normal success must reject wrong provenance bytes.'; Assert-True (Test-Path $journal) 'Wrong provenance verification must retain the transaction journal.'
    }
    finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpSuccessRejectsDeployedExecutableToctouBeforeJournalDelete {
    $root=New-FixtureRoot
    try {
        $target=Join-Path $root 'yt-dlp.exe'; $asset=Join-Path $root 'asset.exe'; $journal=Join-Path $root 'yt-dlp-transaction.json'; [IO.File]::WriteAllText($target,'old-binary',[Text.Encoding]::ASCII); [IO.File]::WriteAllText($asset,'new-binary',[Text.Encoding]::ASCII); $hash=(Get-FileHash $asset -Algorithm SHA256).Hash
        $writer={param($Path,$Manifest) [IO.File]::WriteAllText($Path,($Manifest|ConvertTo-Json),[Text.UTF8Encoding]::new($false)); [IO.File]::WriteAllText($target,'attacker-binary',[Text.Encoding]::ASCII)}.GetNewClosure()
        try { Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader {param($Path) if([IO.File]::ReadAllText($Path,[Text.Encoding]::ASCII)-eq'old-binary'){'previous-tag'}else{'test-tag'}} -ProvenanceWriter $writer | Out-Null; $threw=$false } catch {$threw=$true}
        Assert-True $threw 'Normal success must reject a deployed executable changed after provenance write.'; Assert-True (Test-Path $journal) 'Deployed executable TOCTOU detection must retain the transaction journal.'
    }
    finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-LockedYtDlpSnapshotPinsIdentityAgainstPathSwap {
    $root=New-FixtureRoot
    try {
        $backup=Join-Path $root 'yt-dlp.exe.backup-20260813120000.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; [IO.File]::WriteAllText($backup,'old-binary',[Text.Encoding]::ASCII); $module=$script:runtimeMaintenanceModule
        $result=& $module {
            param($BackupPath,$Directory)
            $snapshot=Open-LockedYtDlpSnapshot -BackupPath $BackupPath -TargetDirectory $Directory
            try {
                $moveBlocked=$false; $writeBlocked=$false
                try { Move-Item -LiteralPath $snapshot.Path -Destination ($snapshot.Path+'.moved') -Force } catch { $moveBlocked=$true }
                try { [IO.File]::WriteAllText($snapshot.Path,'attacker-binary',[Text.Encoding]::ASCII) } catch { $writeBlocked=$true }
                return [pscustomobject]@{MoveBlocked=$moveBlocked;WriteBlocked=$writeBlocked;Hash=(Get-StreamSha256 $snapshot.Stream)}
            }
            finally { Close-LockedYtDlpSnapshot $snapshot }
        } $backup $root
        Assert-True $result.MoveBlocked 'A pinned snapshot path must not be replaceable or deletable.'; Assert-True $result.WriteBlocked 'A pinned snapshot must not be writable.'; Assert-Equal (Get-FileHash $backup -Algorithm SHA256).Hash $result.Hash 'The pinned stream must retain the copied backup identity.'
    }
    finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpRollbackRejectsMutatedGeneratedBackupBeforeTargetMutation {
    $root=New-FixtureRoot
    try {
        $target=Join-Path $root 'yt-dlp.exe';$asset=Join-Path $root 'asset.exe';$journal=Join-Path $root 'yt-dlp-transaction.json';$marker=Join-Path $root 'backup-mutated';[IO.File]::WriteAllText($target,'old-binary',[Text.Encoding]::ASCII);[IO.File]::WriteAllText($asset,'new-binary',[Text.Encoding]::ASCII);$hash=(Get-FileHash $asset -Algorithm SHA256).Hash
        $writer={param($Path,$Manifest) if ((Split-Path -Leaf $Path) -eq 'yt-dlp-transaction.json') { [IO.File]::WriteAllText($Path,($Manifest|ConvertTo-Json),[Text.UTF8Encoding]::new($false)); return }; [IO.File]::WriteAllText([string]$Manifest.backupPath,'attacker-binary',[Text.Encoding]::ASCII); [IO.File]::WriteAllText($marker,'yes',[Text.Encoding]::ASCII); throw 'writer_failed_after_backup_swap'}.GetNewClosure()
        try { Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-ContentVersionReader @{'old-binary'='previous-tag';'new-binary'='test-tag'}) -ProvenanceWriter $writer|Out-Null;$threw=$false } catch {$threw=$true}
        Assert-True $threw 'A mutated generated rollback backup must fail the update.'; Assert-True (Test-Path $marker) 'The fixture must mutate the generated backup before throwing.'; Assert-Equal 'new-binary' ([IO.File]::ReadAllText($target)) 'Catch rollback must not contaminate the target from a mutated backup.'; Assert-True (Test-Path $journal) 'A rejected rollback backup must retain the journal.'
    }
    finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionRollsBackPostReplacementFailure {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        try { Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'test-tag') -SimulatePostReplaceFailure | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'A post-replacement failure must be reported.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'A post-replacement failure must restore the backup.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-YtDlpTransactionWhatIfDoesNotReplace {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        Invoke-FixtureYtDlpTransaction -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'test-tag') -WhatIf | Out-Null
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'WhatIf must not replace the target.'
        Assert-Equal 0 @((Get-ChildItem -LiteralPath $root -Filter 'yt-dlp.exe.staging.*')).Count 'WhatIf must remove its staging fixture.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

$tests = @(
    'Test-RepairSettingsPreservesUnrelatedValues',
    'Test-RepairSettingsLeavesMalformedInputUntouched',
    'Test-RepairSettingsWhatIfDoesNotReplace',
    'Test-RepairSettingsPreservesValidJsonBomAndNoBom',
    'Test-RuntimeMaintenanceModuleExportsOnlyPublicCommands',
    'Test-UpdateYtDlpRejectsCallerControlledSeams',
    'Test-UpdateYtDlpDeclinedConfirmDoesNotReplace',
    'Test-UpdateYtDlpWhatIfVerifiesWithoutReplacing',
    'Test-YtDlpTransactionBlocksHashMismatch',
    'Test-YtDlpTransactionBlocksVersionMismatch',
    'Test-YtDlpTransactionRejectsNonCanonicalTarget',
    'Test-YtDlpTransactionRejectsTraversalTarget',
    'Test-YtDlpTransactionWritesCanonicalSiblingProvenance',
    'Test-YtDlpTransactionRecordsPreviousVersionInProvenance',
    'Test-YtDlpTransactionRestoresProvenanceAfterCommitFailure',
    'Test-YtDlpTransactionRecoversInterruptedReplacementFromJournal',
    'Test-YtDlpTransactionRejectsCorruptJournalBackupBeforeOverwrite',
    'Test-UpdateYtDlpRecoversPendingTransactionBeforeMetadataFetch',
    'Test-YtDlpRecoveryRejectsPreviousVersionMismatchBeforeMutation',
    'Test-YtDlpRecoveryRejectsMalformedProvenanceBase64BeforeMutation',
    'Test-YtDlpTransactionWhatIfDoesNotRecoverPendingJournal',
    'Test-YtDlpRecoveryRejectsUntrustedBackupPathsBeforeExecution',
    'Test-YtDlpRecoveryRequiresTypedJournalSchemaAndEmptyAbsentPreimage',
    'Test-YtDlpRecoveryRetainsJournalWhenProvenanceVerificationFails',
    'Test-YtDlpRollbackRetainsJournalWhenProvenanceVerificationFails',
    'Test-YtDlpRecoveryHandlesPreReplaceJournal',
    'Test-YtDlpRecoveryRejectsMissingBackupWithoutMutation',
    'Test-YtDlpRecoveryReplayIsIdempotent',
    'Test-YtDlpRecoveryRejectsSelfDeclaredBackupIdentity',
    'Test-UpdateYtDlpRejectsElevatedExecutionBeforeRecovery',
    'Test-YtDlpRecoveryKeepsSnapshotWriteLockedThroughRestore',
    'Test-YtDlpSuccessRejectsWrongProvenanceBeforeJournalDelete',
    'Test-YtDlpSuccessRejectsDeployedExecutableToctouBeforeJournalDelete',
    'Test-LockedYtDlpSnapshotPinsIdentityAgainstPathSwap',
    'Test-YtDlpRollbackRejectsMutatedGeneratedBackupBeforeTargetMutation',
    'Test-YtDlpTransactionRollsBackPostReplacementFailure',
    'Test-YtDlpTransactionWhatIfDoesNotReplace'
)
foreach ($test in $tests) {
    if ([string]::IsNullOrWhiteSpace($TestFilter) -or $test -eq $TestFilter) { & $test }
}

if ($script:failures.Count -gt 0) {
    $script:failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'runtime-maintenance tests passed'
