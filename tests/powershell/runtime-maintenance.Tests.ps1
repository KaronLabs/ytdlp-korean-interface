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

function Invoke-FixtureYtDlpTransaction {
    param(
        [string] $TargetPath,
        [string] $AssetPath,
        [string] $ReleaseTag,
        [string] $ExpectedSha256,
        [scriptblock] $VersionReader,
        [switch] $SimulatePostReplaceFailure,
        [switch] $WhatIf
    )
    $module = $script:runtimeMaintenanceModule
    & $module {
        param($TargetPath, $AssetPath, $ReleaseTag, $ExpectedSha256, $VersionReader, $SimulatePostReplaceFailure, $WhatIf)
        Invoke-YtDlpTransaction -TargetPath $TargetPath -AssetPath $AssetPath -ReleaseTag $ReleaseTag -ExpectedSha256 $ExpectedSha256 -VersionReader $VersionReader -SimulatePostReplaceFailure:$SimulatePostReplaceFailure -WhatIf:$WhatIf -Confirm:$false
    } $TargetPath $AssetPath $ReleaseTag $ExpectedSha256 $VersionReader $SimulatePostReplaceFailure $WhatIf
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

Test-RepairSettingsPreservesUnrelatedValues
Test-RepairSettingsLeavesMalformedInputUntouched
Test-RepairSettingsWhatIfDoesNotReplace
Test-RepairSettingsPreservesValidJsonBomAndNoBom
Test-RuntimeMaintenanceModuleExportsOnlyPublicCommands
Test-UpdateYtDlpRejectsCallerControlledSeams
Test-UpdateYtDlpDeclinedConfirmDoesNotReplace
Test-UpdateYtDlpWhatIfVerifiesWithoutReplacing
Test-YtDlpTransactionBlocksHashMismatch
Test-YtDlpTransactionBlocksVersionMismatch
Test-YtDlpTransactionRejectsNonCanonicalTarget
Test-YtDlpTransactionRejectsTraversalTarget
Test-YtDlpTransactionWritesCanonicalSiblingProvenance
Test-YtDlpTransactionRollsBackPostReplacementFailure
Test-YtDlpTransactionWhatIfDoesNotReplace

if ($script:failures.Count -gt 0) {
    $script:failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'runtime-maintenance tests passed'
