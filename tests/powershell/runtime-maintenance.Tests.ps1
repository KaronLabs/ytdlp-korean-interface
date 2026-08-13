$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$toolPath = Join-Path $repositoryRoot 'tools/runtime-maintenance.ps1'
if (-not (Test-Path -LiteralPath $toolPath)) {
    throw 'runtime-maintenance.ps1 is missing'
}
. $toolPath

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
    param([string] $Path)
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
    [System.IO.File]::WriteAllText($Path, ($fixture | ConvertTo-Json -Depth 10), [System.Text.Encoding]::UTF8)
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
        Assert-True (Test-Path -LiteralPath $result.BackupPath) 'A settings backup should exist before replacement.'
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

function Test-UpdateYtDlpBlocksHashMismatch {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        try { UpdateYtDlp -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 ('0' * 64) -VersionReader (New-VersionReader 'test-tag') -Confirm:$false | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'A hash mismatch must block replacement.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'A hash mismatch must retain the target.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-UpdateYtDlpBlocksVersionMismatch {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        try { UpdateYtDlp -TargetPath $target -AssetPath $asset -ReleaseTag 'expected-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'wrong-tag') -Confirm:$false | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'A staged version mismatch must block replacement.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'A version mismatch must retain the target.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-UpdateYtDlpRejectsAlternateRepository {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        try { UpdateYtDlp -TargetPath $target -Repository 'example/not-official' -Confirm:$false | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'An alternate repository must be rejected before network access.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'An alternate repository must retain the target.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-UpdateYtDlpWritesProvenanceAfterVerifiedReplacement {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        $provenance = Join-Path $root 'provenance.json'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash

        $result = UpdateYtDlp -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'test-tag') -ProvenancePath $provenance -Confirm:$false
        $manifest = Get-Content -LiteralPath $provenance -Raw | ConvertFrom-Json

        Assert-True $result.Updated 'Verified asset should replace the target.'
        Assert-Equal 'new-binary' ([System.IO.File]::ReadAllText($target)) 'The verified asset should be deployed.'
        Assert-Equal 'yt-dlp/yt-dlp-nightly-builds' $manifest.repository 'Provenance must identify the official repository.'
        Assert-Equal $hash $manifest.sha256 'Provenance must record the verified hash.'
        Assert-True (Test-Path -LiteralPath $result.BackupPath) 'The previous target must be retained as a backup.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-UpdateYtDlpRollsBackPostReplacementFailure {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        try { UpdateYtDlp -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'test-tag') -SimulatePostReplaceFailure -Confirm:$false | Out-Null; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'A post-replacement failure must be reported.'
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'A post-replacement failure must restore the backup.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-UpdateYtDlpWhatIfDoesNotReplace {
    $root = New-FixtureRoot
    try {
        $target = Join-Path $root 'yt-dlp.exe'
        $asset = Join-Path $root 'asset.exe'
        [System.IO.File]::WriteAllText($target, 'old-binary', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($asset, 'new-binary', [System.Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
        UpdateYtDlp -TargetPath $target -AssetPath $asset -ReleaseTag 'test-tag' -ExpectedSha256 $hash -VersionReader (New-VersionReader 'test-tag') -WhatIf | Out-Null
        Assert-Equal 'old-binary' ([System.IO.File]::ReadAllText($target)) 'WhatIf must not replace the target.'
        Assert-Equal 0 @((Get-ChildItem -LiteralPath $root -Filter 'yt-dlp.exe.staging.*')).Count 'WhatIf must remove its staging fixture.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-RepairSettingsPreservesUnrelatedValues
Test-RepairSettingsLeavesMalformedInputUntouched
Test-RepairSettingsWhatIfDoesNotReplace
Test-UpdateYtDlpBlocksHashMismatch
Test-UpdateYtDlpBlocksVersionMismatch
Test-UpdateYtDlpRejectsAlternateRepository
Test-UpdateYtDlpWritesProvenanceAfterVerifiedReplacement
Test-UpdateYtDlpRollsBackPostReplacementFailure
Test-UpdateYtDlpWhatIfDoesNotReplace

if ($script:failures.Count -gt 0) {
    $script:failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'runtime-maintenance tests passed'
