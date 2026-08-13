Set-StrictMode -Version Latest

$script:OfficialNightlyRepository = 'yt-dlp/yt-dlp-nightly-builds'

function Get-DownloadsKnownFolderPath {
    if (-not ('RuntimeMaintenance.NativeKnownFolders' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace RuntimeMaintenance {
    public static class NativeKnownFolders {
        [DllImport("shell32.dll")]
        public static extern int SHGetKnownFolderPath(ref Guid knownFolderId, uint flags, IntPtr token, out IntPtr path);
    }
}
'@
    }

    $downloadsId = [Guid]'374DE290-123F-4565-9164-39C4925E467B'
    $pointer = [IntPtr]::Zero
    $result = [RuntimeMaintenance.NativeKnownFolders]::SHGetKnownFolderPath([ref]$downloadsId, 0, [IntPtr]::Zero, [ref]$pointer)
    if ($result -ne 0) { throw "Could not resolve FOLDERID_Downloads (HRESULT 0x{0:X8})." -f $result }
    try { return [Runtime.InteropServices.Marshal]::PtrToStringUni($pointer) }
    finally { if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeCoTaskMem($pointer) } }
}

function Test-StaleDownloadPath {
    param([object] $Value)
    if ($Value -isnot [string]) { return $false }
    return $Value.StartsWith('D:\Luna-Youtube-Downloader', [StringComparison]::OrdinalIgnoreCase) -or
        $Value.StartsWith('C:\Users\Administrator', [StringComparison]::OrdinalIgnoreCase)
}

function Get-PropertyValue {
    param([object] $Object, [string] $Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-PropertyValue {
    param([object] $Object, [string] $Name, $Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
    else { $property.Value = $Value }
}

function Repair-PathFields {
    param([object] $Settings, [string] $DownloadsPath)
    $changed = $false
    $outpath = Get-PropertyValue $Settings 'outpath'
    if (Test-StaleDownloadPath $outpath) {
        Set-PropertyValue $Settings 'outpath' $DownloadsPath
        $changed = $true
    }

    $outpaths = Get-PropertyValue $Settings 'outpaths'
    if ($null -ne $outpaths) {
        $kept = New-Object System.Collections.Generic.List[string]
        foreach ($path in @($outpaths)) {
            if (Test-StaleDownloadPath $path) { $changed = $true; continue }
            if ($path -is [string]) { $kept.Add($path) }
        }
        if (-not ($kept | Where-Object { $_.Equals($DownloadsPath, [StringComparison]::OrdinalIgnoreCase) })) {
            $kept.Insert(0, $DownloadsPath)
            $changed = $true
        }
        if ($changed) { Set-PropertyValue $Settings 'outpaths' @($kept) }
    }
    return $changed
}

function New-SiblingPath {
    param([string] $Path, [string] $Suffix)
    return (Join-Path (Split-Path -Parent $Path) ((Split-Path -Leaf $Path) + '.' + $Suffix + '.' + [Guid]::NewGuid().ToString('N')))
}

function Write-JsonTransactionFile {
    param([object] $Value, [string] $Path, [string] $BackupPath)
    $temporaryPath = New-SiblingPath $Path 'temporary'
    try {
        [IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), [Text.Encoding]::UTF8)
        Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json | Out-Null
        [IO.File]::Replace($temporaryPath, $Path, $BackupPath, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

function RepairSettings {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)] [string] $SettingsPath,
        [string] $DownloadsPath
    )

    $resolvedSettingsPath = (Resolve-Path -LiteralPath $SettingsPath -ErrorAction Stop).Path
    if ([string]::IsNullOrWhiteSpace($DownloadsPath)) { $DownloadsPath = Get-DownloadsKnownFolderPath }
    $downloadsFullPath = [IO.Path]::GetFullPath($DownloadsPath)
    try { $settings = (Get-Content -LiteralPath $resolvedSettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop) }
    catch { throw 'Settings JSON is malformed; the original file was not changed.' }

    $changed = Repair-PathFields $settings $downloadsFullPath
    foreach ($preset in @((Get-PropertyValue $settings 'presets'))) {
        if ($null -ne $preset) { if (Repair-PathFields $preset $downloadsFullPath) { $changed = $true } }
    }
    if (-not $changed) { return [pscustomobject]@{ Changed = $false; BackupPath = $null; WhatIf = $WhatIfPreference } }
    if (-not $PSCmdlet.ShouldProcess($resolvedSettingsPath, 'replace repaired settings')) {
        return [pscustomobject]@{ Changed = $true; BackupPath = $null; WhatIf = $true }
    }

    $backupPath = New-SiblingPath $resolvedSettingsPath ('backup-' + (Get-Date -Format 'yyyyMMddHHmmss'))
    try {
        Write-JsonTransactionFile $settings $resolvedSettingsPath $backupPath
        Get-Content -LiteralPath $resolvedSettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null
    }
    catch {
        if (Test-Path -LiteralPath $backupPath) { [IO.File]::Copy($backupPath, $resolvedSettingsPath, $true) }
        throw
    }
    return [pscustomobject]@{ Changed = $true; BackupPath = $backupPath; WhatIf = $false }
}

function Get-Sha256 {
    param([string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-OfficialNightlyAsset {
    param([string] $StagingPath)
    $release = Invoke-RestMethod -Uri ('https://api.github.com/repos/{0}/releases/latest' -f $script:OfficialNightlyRepository) -Headers @{ 'User-Agent' = 'ytdlp-interface-runtime-maintenance' }
    $asset = @($release.assets | Where-Object { $_.name -eq 'yt-dlp.exe' }) | Select-Object -First 1
    $sums = @($release.assets | Where-Object { $_.name -match '^SHA2-256SUMS(\.txt)?$' }) | Select-Object -First 1
    if ($null -eq $asset -or $null -eq $sums -or [string]::IsNullOrWhiteSpace($release.tag_name)) { throw 'Official nightly release metadata lacks yt-dlp.exe or SHA2-256SUMS.' }
    $assetPath = Join-Path $StagingPath 'yt-dlp.exe'
    $sumsPath = Join-Path $StagingPath 'SHA2-256SUMS'
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $assetPath
    Invoke-WebRequest -UseBasicParsing -Uri $sums.browser_download_url -OutFile $sumsPath
    $line = Select-String -LiteralPath $sumsPath -Pattern '^\s*([a-fA-F0-9]{64})\s+\*?yt-dlp\.exe\s*$' | Select-Object -First 1
    if ($null -eq $line) { throw 'Official SHA2-256SUMS does not contain yt-dlp.exe.' }
    return [pscustomobject]@{ AssetPath = $assetPath; ReleaseTag = [string]$release.tag_name; ExpectedSha256 = $line.Matches[0].Groups[1].Value }
}

function Get-YtDlpVersion {
    param([string] $Path, [scriptblock] $VersionReader)
    if ($null -ne $VersionReader) { return [string](& $VersionReader $Path) }
    $outputPath = New-SiblingPath $Path 'version'
    try {
        $process = Start-Process -FilePath $Path -ArgumentList '--version' -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outputPath
        if ($process.ExitCode -ne 0) { throw 'yt-dlp --version failed.' }
        return (Get-Content -LiteralPath $outputPath -Raw).Trim()
    }
    finally { if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue } }
}

function Restore-BackupFile {
    param([string] $BackupPath, [string] $TargetPath)
    $restorePath = New-SiblingPath $TargetPath 'rollback'
    $rollbackBackupPath = New-SiblingPath $TargetPath 'rollback-backup'
    try {
        [IO.File]::Copy($BackupPath, $restorePath, $true)
        [IO.File]::Replace($restorePath, $TargetPath, $rollbackBackupPath, $true)
    }
    finally {
        if (Test-Path -LiteralPath $restorePath) { Remove-Item -LiteralPath $restorePath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $rollbackBackupPath) { Remove-Item -LiteralPath $rollbackBackupPath -Force -ErrorAction SilentlyContinue }
    }
}

function UpdateYtDlp {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)] [string] $TargetPath,
        [string] $Repository = 'yt-dlp/yt-dlp-nightly-builds',
        [string] $AssetPath,
        [string] $ReleaseTag,
        [string] $ExpectedSha256,
        [scriptblock] $VersionReader,
        [string] $ProvenancePath,
        [switch] $SimulatePostReplaceFailure
    )

    if ($Repository -cne $script:OfficialNightlyRepository) { throw 'Only yt-dlp/yt-dlp-nightly-builds is permitted.' }
    $resolvedTargetPath = (Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop).Path
    $stagingPath = New-SiblingPath $resolvedTargetPath 'staging'
    [IO.Directory]::CreateDirectory($stagingPath) | Out-Null
    try {
        if ([string]::IsNullOrWhiteSpace($AssetPath)) {
            $official = Get-OfficialNightlyAsset $stagingPath
            $AssetPath = $official.AssetPath; $ReleaseTag = $official.ReleaseTag; $ExpectedSha256 = $official.ExpectedSha256
        }
        elseif (-not (Test-Path -LiteralPath $AssetPath)) { throw 'The supplied asset fixture does not exist.' }
        if ([string]::IsNullOrWhiteSpace($ReleaseTag) -or [string]::IsNullOrWhiteSpace($ExpectedSha256)) { throw 'ReleaseTag and ExpectedSha256 are required for a supplied asset fixture.' }

        $stagedAssetPath = Join-Path $stagingPath 'yt-dlp.exe'
        [IO.File]::Copy((Resolve-Path -LiteralPath $AssetPath).Path, $stagedAssetPath, $true)
        $actualHash = Get-Sha256 $stagedAssetPath
        if ($actualHash -cne $ExpectedSha256.ToUpperInvariant()) { throw 'The yt-dlp SHA-256 does not match the official checksum.' }
        if ((Get-YtDlpVersion $stagedAssetPath $VersionReader) -cne $ReleaseTag) { throw 'The staged yt-dlp version does not match the release tag.' }
        if (-not $PSCmdlet.ShouldProcess($resolvedTargetPath, 'replace verified yt-dlp nightly')) {
            return [pscustomobject]@{ Updated = $false; BackupPath = $null; WhatIf = $true; Sha256 = $actualHash }
        }

        $backupPath = New-SiblingPath $resolvedTargetPath ('backup-' + (Get-Date -Format 'yyyyMMddHHmmss'))
        [IO.File]::Replace($stagedAssetPath, $resolvedTargetPath, $backupPath, $true)
        try {
            if ($SimulatePostReplaceFailure) { throw 'Simulated post-replacement failure.' }
            if ((Get-YtDlpVersion $resolvedTargetPath $VersionReader) -cne $ReleaseTag) { throw 'The deployed yt-dlp version does not match the release tag.' }
            if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { $ProvenancePath = Join-Path (Split-Path -Parent $resolvedTargetPath) 'yt-dlp-provenance.json' }
            $provenance = [ordered]@{ repository = $script:OfficialNightlyRepository; channel = 'nightly'; tag = $ReleaseTag; asset = 'yt-dlp.exe'; sha256 = $actualHash; installedAtUtc = [DateTime]::UtcNow.ToString('o'); backupPath = $backupPath }
            [IO.File]::WriteAllText($ProvenancePath, ($provenance | ConvertTo-Json), [Text.Encoding]::UTF8)
        }
        catch {
            Restore-BackupFile $backupPath $resolvedTargetPath
            if ((Get-YtDlpVersion $resolvedTargetPath $VersionReader) -ne (Get-YtDlpVersion $backupPath $VersionReader)) { throw 'Rollback verification failed after update failure.' }
            throw
        }
        return [pscustomobject]@{ Updated = $true; BackupPath = $backupPath; WhatIf = $false; Sha256 = $actualHash }
    }
    finally {
        if (Test-Path -LiteralPath $stagingPath) { Remove-Item -LiteralPath $stagingPath -Recurse -Force -WhatIf:$false -ErrorAction SilentlyContinue }
    }
}
