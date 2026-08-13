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

function Get-JsonFile {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = New-Object Text.UTF8Encoding($true)
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $encoding = [Text.Encoding]::Unicode }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $encoding = [Text.Encoding]::BigEndianUnicode }
    else { $encoding = New-Object Text.UTF8Encoding($false) }
    try { $value = ([IO.File]::ReadAllText($Path, $encoding) | ConvertFrom-Json -ErrorAction Stop) }
    catch { throw 'Settings JSON is malformed; the original file was not changed.' }
    return [pscustomobject]@{ Value = $value; Encoding = $encoding }
}

function Repair-PathFields {
    param([object] $Settings, [string] $DownloadsPath)
    $changed = $false
    $outpath = Get-PropertyValue $Settings 'outpath'
    if (Test-StaleDownloadPath $outpath) { Set-PropertyValue $Settings 'outpath' $DownloadsPath; $changed = $true }
    $outpaths = Get-PropertyValue $Settings 'outpaths'
    if ($null -ne $outpaths) {
        $kept = New-Object System.Collections.Generic.List[object]
        $outpathsChanged = $false
        $hasDownloadsPath = $false
        foreach ($path in @($outpaths)) {
            if (Test-StaleDownloadPath $path) {
                if (-not $hasDownloadsPath) { $kept.Add($DownloadsPath); $hasDownloadsPath = $true }
                $changed = $true; $outpathsChanged = $true; continue
            }
            $kept.Add($path)
            if ($path -is [string] -and $path.Equals($DownloadsPath, [StringComparison]::OrdinalIgnoreCase)) { $hasDownloadsPath = $true }
        }
        if ($outpathsChanged) { Set-PropertyValue $Settings 'outpaths' $kept.ToArray() }
    }
    return $changed
}

function New-SiblingPath {
    param([string] $Path, [string] $Suffix)
    return (Join-Path (Split-Path -Parent $Path) ((Split-Path -Leaf $Path) + '.' + $Suffix + '.' + [Guid]::NewGuid().ToString('N')))
}

function Write-JsonTransactionFile {
    param([object] $Value, [string] $Path, [string] $BackupPath, [Text.Encoding] $Encoding)
    $temporaryPath = New-SiblingPath $Path 'temporary'
    try {
        [IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $Encoding)
        Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json | Out-Null
        [IO.File]::Replace($temporaryPath, $Path, $BackupPath, $true)
    }
    finally { if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } }
}

function RepairSettings {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory = $true)] [string] $SettingsPath, [string] $DownloadsPath)
    $resolvedSettingsPath = (Resolve-Path -LiteralPath $SettingsPath -ErrorAction Stop).Path
    if ([string]::IsNullOrWhiteSpace($DownloadsPath)) { $DownloadsPath = Get-DownloadsKnownFolderPath }
    $settingsFile = Get-JsonFile $resolvedSettingsPath
    $settings = $settingsFile.Value
    $changed = Repair-PathFields $settings ([IO.Path]::GetFullPath($DownloadsPath))
    foreach ($preset in @((Get-PropertyValue $settings 'presets'))) {
        if ($null -ne $preset -and (Repair-PathFields $preset ([IO.Path]::GetFullPath($DownloadsPath))) ) { $changed = $true }
    }
    if (-not $changed) { return [pscustomobject]@{ Changed = $false; BackupPath = $null; WhatIf = $WhatIfPreference } }
    if (-not $PSCmdlet.ShouldProcess($resolvedSettingsPath, 'replace repaired settings')) { return [pscustomobject]@{ Changed = $true; BackupPath = $null; WhatIf = $true } }
    $backupPath = New-SiblingPath $resolvedSettingsPath ('backup-' + (Get-Date -Format 'yyyyMMddHHmmss'))
    try {
        Write-JsonTransactionFile $settings $resolvedSettingsPath $backupPath $settingsFile.Encoding
        Get-Content -LiteralPath $resolvedSettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null
    }
    catch {
        if (Test-Path -LiteralPath $backupPath) { Restore-BackupFile $backupPath $resolvedSettingsPath }
        throw
    }
    return [pscustomobject]@{ Changed = $true; BackupPath = $backupPath; WhatIf = $false }
}

function Get-Sha256 { param([string] $Path) return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }

function Get-StreamSha256 {
    param([Parameter(Mandatory = $true)] [IO.Stream] $Stream)
    $position = $Stream.Position
    try {
        $Stream.Position = 0
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { return (($algorithm.ComputeHash($Stream) | ForEach-Object { $_.ToString('X2') }) -join '') }
        finally { $algorithm.Dispose() }
    }
    finally { $Stream.Position = $position }
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OfficialNightlyAsset {
    param([string] $StagingPath)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri ('https://api.github.com/repos/{0}/releases/latest' -f $script:OfficialNightlyRepository) -Headers @{ 'User-Agent' = 'ytdlp-interface-runtime-maintenance' }
    $asset = @($release.assets | Where-Object { $_.name -eq 'yt-dlp.exe' }) | Select-Object -First 1
    $sums = @($release.assets | Where-Object { $_.name -match '^SHA2-256SUMS(\.txt)?$' }) | Select-Object -First 1
    if ($null -eq $asset -or $null -eq $sums -or [string]::IsNullOrWhiteSpace($release.tag_name)) { throw 'Official nightly release metadata lacks yt-dlp.exe or SHA2-256SUMS.' }
    $assetPath = Join-Path $StagingPath 'yt-dlp.exe'; $sumsPath = Join-Path $StagingPath 'SHA2-256SUMS'
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
    $restorePath = New-SiblingPath $TargetPath 'rollback'; $rollbackBackupPath = New-SiblingPath $TargetPath 'rollback-backup'
    try { [IO.File]::Copy($BackupPath, $restorePath, $true); [IO.File]::Replace($restorePath, $TargetPath, $rollbackBackupPath, $true) }
    finally {
        if (Test-Path -LiteralPath $restorePath) { Remove-Item -LiteralPath $restorePath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $rollbackBackupPath) { Remove-Item -LiteralPath $rollbackBackupPath -Force -ErrorAction SilentlyContinue }
    }
}

function Write-ProvenanceAtomically {
    param([Parameter(Mandatory = $true)] [string] $Path, [Parameter(Mandatory = $true)] [object] $Manifest)
    $temporaryPath = New-SiblingPath $Path 'staging'; $backupPath = New-SiblingPath $Path 'replace-backup'
    try {
        [IO.File]::WriteAllText($temporaryPath, ($Manifest | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json | Out-Null
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($temporaryPath, $Path, $backupPath, $true) }
        else { [IO.File]::Move($temporaryPath, $Path) }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
    }
}

function Restore-FilePreimage {
    param([Parameter(Mandatory = $true)] [string] $Path, [byte[]] $Bytes, [bool] $Existed)
    if (-not $Existed) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { Remove-Item -LiteralPath $Path -Force }
        return
    }
    $temporaryPath = New-SiblingPath $Path 'restore'; $backupPath = New-SiblingPath $Path 'restore-backup'
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($temporaryPath, $Path, $backupPath, $true) }
        else { [IO.File]::Move($temporaryPath, $Path) }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
    }
}

function Test-FilePreimage {
    param([Parameter(Mandatory = $true)] [string] $Path, [byte[]] $Bytes, [bool] $Existed)
    if (-not $Existed) { return -not (Test-Path -LiteralPath $Path) }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) -ceq [Convert]::ToBase64String($Bytes)
}

function Open-LockedYtDlpSnapshot {
    param([Parameter(Mandatory = $true)] [string] $BackupPath, [Parameter(Mandatory = $true)] [string] $TargetDirectory)
    $item = Get-Item -LiteralPath $BackupPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) { throw 'The yt-dlp backup must not be a link or reparse point.' }
    $path = Join-Path $TargetDirectory ('yt-dlp.recovery-snapshot.' + [Guid]::NewGuid().ToString('N') + '.exe')
    $source = $null; $writer = $null; $bridge = $null; $reader = $null
    try {
        $source = [IO.File]::Open($BackupPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $writer = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
        $source.CopyTo($writer); $writer.Flush($true)
        $bridge = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $writer.Dispose(); $writer = $null
        $reader = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $bridge.Dispose(); $bridge = $null
        return [pscustomobject]@{ Path = $path; Stream = $reader }
    }
    catch { if ($null -ne $reader) { $reader.Dispose() }; if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }; throw }
    finally { if ($null -ne $source) { $source.Dispose() }; if ($null -ne $writer) { $writer.Dispose() }; if ($null -ne $bridge) { $bridge.Dispose() } }
}

function Close-LockedYtDlpSnapshot {
    param([Parameter(Mandatory = $true)] [object] $Snapshot)
    $Snapshot.Stream.Dispose()
    if (Test-Path -LiteralPath $Snapshot.Path) { Remove-Item -LiteralPath $Snapshot.Path -Force -ErrorAction SilentlyContinue }
}

function Get-YtDlpTransactionJournalPath {
    param([Parameter(Mandatory = $true)] [string] $TargetPath)
    return Join-Path (Split-Path -Parent $TargetPath) 'yt-dlp-transaction.json'
}

function Write-YtDlpTransactionJournal {
    param([Parameter(Mandatory = $true)] [string] $Path, [Parameter(Mandatory = $true)] [object] $Record)
    Write-ProvenanceAtomically -Path $Path -Manifest $Record
}

function Remove-YtDlpTransactionJournal {
    param([Parameter(Mandatory = $true)] [string] $Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Remove-Item -LiteralPath $Path -Force }
}

function Restore-PendingYtDlpTransaction {
    param([Parameter(Mandatory = $true)] [string] $TargetPath, [scriptblock] $VersionReader)
    $journalPath = Get-YtDlpTransactionJournalPath -TargetPath $TargetPath
    if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) { return }
    $record = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
    foreach ($field in @('schemaVersion', 'targetPath', 'backupPath', 'previousVersion', 'previousSha256', 'provenanceExisted', 'provenanceBytesBase64')) {
        if ($null -eq $record.PSObject.Properties[$field]) { throw 'The pending yt-dlp transaction journal is invalid.' }
    }
    if (($record.schemaVersion -isnot [int] -and $record.schemaVersion -isnot [long]) -or $record.schemaVersion -ne 1 -or
        $record.targetPath -isnot [string] -or $record.backupPath -isnot [string] -or $record.previousVersion -isnot [string] -or
        $record.previousSha256 -isnot [string] -or $record.provenanceExisted -isnot [bool] -or $record.provenanceBytesBase64 -isnot [string]) { throw 'The pending yt-dlp transaction journal is invalid.' }
    if ([IO.Path]::GetFullPath($record.targetPath) -cne $TargetPath) { throw 'The pending yt-dlp transaction journal is invalid.' }
    $previousSha256 = $record.previousSha256.ToUpperInvariant()
    if ($previousSha256 -notmatch '^[A-F0-9]{64}$') { throw 'The pending yt-dlp transaction journal has no valid prior hash.' }
    $previousVersion = [string]$record.previousVersion
    if ([string]::IsNullOrWhiteSpace($previousVersion)) { throw 'The pending yt-dlp transaction journal has no valid prior version.' }
    $backupPath = $record.backupPath
    $targetDirectory = Split-Path -Parent $TargetPath
    $expectedBackupLeaf = '^' + [regex]::Escape((Split-Path -Leaf $TargetPath) + '.backup-') + '\d{14}\.[A-Fa-f0-9]{32}$'
    if (-not [IO.Path]::IsPathRooted($backupPath) -or [IO.Path]::GetFullPath((Split-Path -Parent $backupPath)) -cne $targetDirectory -or (Split-Path -Leaf $backupPath) -notmatch $expectedBackupLeaf) { throw 'The pending yt-dlp transaction backup path is invalid.' }
    $provenanceExisted = $record.provenanceExisted
    [byte[]]$provenanceBytes = [Convert]::FromBase64String($record.provenanceBytesBase64)
    if (-not $provenanceExisted -and $provenanceBytes.Length -ne 0) { throw 'The pending yt-dlp transaction provenance preimage is invalid.' }
    if ($provenanceExisted) {
        try { $priorProvenance = [Text.UTF8Encoding]::new($false, $true).GetString($provenanceBytes) | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'The pending yt-dlp transaction provenance preimage is invalid.' }
        if ($priorProvenance.repository -cne $script:OfficialNightlyRepository -or $priorProvenance.channel -cne 'nightly' -or
            [string]$priorProvenance.asset -cne 'yt-dlp.exe' -or [string]$priorProvenance.tag -cne $previousVersion -or
            ([string]$priorProvenance.sha256).ToUpperInvariant() -cne $previousSha256) { throw 'The pending yt-dlp transaction prior provenance does not bind the backup identity.' }
    }
    $provenancePath = Join-Path $targetDirectory 'yt-dlp-provenance.json'
    $snapshot = $null
    try {
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            $snapshot = Open-LockedYtDlpSnapshot -BackupPath $backupPath -TargetDirectory $targetDirectory
            if ((Get-StreamSha256 $snapshot.Stream) -cne $previousSha256) { throw 'The pending yt-dlp transaction backup does not match its prior hash.' }
        }
        elseif ((Get-Sha256 $TargetPath) -cne $previousSha256 -or (Get-YtDlpVersion $TargetPath $VersionReader) -cne $previousVersion) { throw 'The pending yt-dlp transaction cannot be recovered because its backup is missing.' }
        if ($null -ne $snapshot) { Restore-BackupFile -BackupPath $snapshot.Path -TargetPath $TargetPath }
        Restore-FilePreimage -Path $provenancePath -Bytes $provenanceBytes -Existed:$provenanceExisted
        if ((Get-Sha256 $TargetPath) -cne $previousSha256 -or -not (Test-FilePreimage -Path $provenancePath -Bytes $provenanceBytes -Existed:$provenanceExisted)) { throw 'Pending yt-dlp transaction recovery verification failed.' }
        Remove-YtDlpTransactionJournal -Path $journalPath
    }
    finally { if ($null -ne $snapshot) { Close-LockedYtDlpSnapshot $snapshot } }
}

function Resolve-CanonicalYtDlpTargetPath {
    param([string] $TargetPath)
    if (@($TargetPath -split '[\\/]' | Where-Object { $_ -eq '..' }).Count -ne 0) { throw 'The target path must not contain traversal components.' }
    $resolvedTargetPath = (Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop).Path
    if ((Split-Path -Leaf $resolvedTargetPath) -cne 'yt-dlp.exe') { throw 'The target must be the canonical yt-dlp.exe file.' }
    return $resolvedTargetPath
}

function Invoke-YtDlpTransaction {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)] [string] $TargetPath,
        [Parameter(Mandatory = $true)] [string] $AssetPath,
        [Parameter(Mandatory = $true)] [string] $ReleaseTag,
        [Parameter(Mandatory = $true)] [string] $ExpectedSha256,
        [scriptblock] $VersionReader, [switch] $SimulatePostReplaceFailure
    )
    $resolvedTargetPath = Resolve-CanonicalYtDlpTargetPath $TargetPath
    if (-not $WhatIfPreference) { Restore-PendingYtDlpTransaction -TargetPath $resolvedTargetPath -VersionReader $VersionReader }
    if (-not (Test-Path -LiteralPath $AssetPath)) { throw 'The supplied asset fixture does not exist.' }
    $provenancePath = Join-Path (Split-Path -Parent $resolvedTargetPath) 'yt-dlp-provenance.json'
    if ((Test-Path -LiteralPath $provenancePath) -and -not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) { throw 'The existing provenance path must be a file.' }
    $hadProvenance = Test-Path -LiteralPath $provenancePath -PathType Leaf
    [byte[]]$previousProvenanceBytes = @()
    if ($hadProvenance) { $previousProvenanceBytes = [IO.File]::ReadAllBytes($provenancePath) }
    $stagingPath = New-SiblingPath $resolvedTargetPath 'staging'
    [IO.Directory]::CreateDirectory($stagingPath) | Out-Null
    try {
        $stagedAssetPath = Join-Path $stagingPath 'yt-dlp.exe'
        [IO.File]::Copy((Resolve-Path -LiteralPath $AssetPath).Path, $stagedAssetPath, $true)
        $actualHash = Get-Sha256 $stagedAssetPath
        if ($actualHash -cne $ExpectedSha256.ToUpperInvariant()) { throw 'The yt-dlp SHA-256 does not match the official checksum.' }
        if ((Get-YtDlpVersion $stagedAssetPath $VersionReader) -cne $ReleaseTag) { throw 'The staged yt-dlp version does not match the release tag.' }
        if (-not $PSCmdlet.ShouldProcess($resolvedTargetPath, 'replace verified yt-dlp nightly')) { return [pscustomobject]@{ Updated = $false; BackupPath = $null; WhatIf = $true; Sha256 = $actualHash } }
        $previousVersion = Get-YtDlpVersion $resolvedTargetPath $VersionReader
        $previousSha256 = Get-Sha256 $resolvedTargetPath
        $backupPath = New-SiblingPath $resolvedTargetPath ('backup-' + (Get-Date -Format 'yyyyMMddHHmmss'))
        $journalPath = Get-YtDlpTransactionJournalPath -TargetPath $resolvedTargetPath
        $journal = [ordered]@{ schemaVersion = 1; targetPath = $resolvedTargetPath; backupPath = $backupPath; previousVersion = $previousVersion; previousSha256 = $previousSha256; provenanceExisted = $hadProvenance; provenanceBytesBase64 = [Convert]::ToBase64String($previousProvenanceBytes) }
        Write-YtDlpTransactionJournal -Path $journalPath -Record $journal
        [IO.File]::Replace($stagedAssetPath, $resolvedTargetPath, $backupPath, $true)
        try {
            if ($SimulatePostReplaceFailure) { throw 'Simulated post-replacement failure.' }
            if ((Get-YtDlpVersion $resolvedTargetPath $VersionReader) -cne $ReleaseTag) { throw 'The deployed yt-dlp version does not match the release tag.' }
            $provenance = [ordered]@{ repository = $script:OfficialNightlyRepository; channel = 'nightly'; tag = $ReleaseTag; asset = 'yt-dlp.exe'; sha256 = $actualHash; installedAtUtc = [DateTime]::UtcNow.ToString('o'); previousVersion = $previousVersion; previousSha256 = $previousSha256; backupPath = $backupPath }
            Write-ProvenanceAtomically -Path $provenancePath -Manifest $provenance
            [byte[]]$expectedProvenanceBytes = [Text.UTF8Encoding]::new($false).GetBytes(($provenance | ConvertTo-Json))
            if ((Get-Sha256 $resolvedTargetPath) -cne $actualHash -or -not (Test-FilePreimage -Path $provenancePath -Bytes $expectedProvenanceBytes -Existed:$true)) { throw 'The committed yt-dlp executable and provenance pair failed verification.' }
            Remove-YtDlpTransactionJournal -Path $journalPath
        }
        catch {
            $rollbackSnapshot = $null
            try {
                $rollbackSnapshot = Open-LockedYtDlpSnapshot -BackupPath $backupPath -TargetDirectory (Split-Path -Parent $resolvedTargetPath)
                if ((Get-StreamSha256 $rollbackSnapshot.Stream) -cne $previousSha256) { throw 'Rollback backup verification failed after update failure.' }
                Restore-BackupFile $rollbackSnapshot.Path $resolvedTargetPath
                Restore-FilePreimage -Path $provenancePath -Bytes $previousProvenanceBytes -Existed:$hadProvenance
                if ((Get-Sha256 $resolvedTargetPath) -cne $previousSha256 -or -not (Test-FilePreimage -Path $provenancePath -Bytes $previousProvenanceBytes -Existed:$hadProvenance)) { throw 'Rollback verification failed after update failure.' }
            }
            finally { if ($null -ne $rollbackSnapshot) { Close-LockedYtDlpSnapshot $rollbackSnapshot } }
            throw
        }
        return [pscustomobject]@{ Updated = $true; BackupPath = $backupPath; WhatIf = $false; Sha256 = $actualHash }
    }
    finally { if (Test-Path -LiteralPath $stagingPath) { Remove-Item -LiteralPath $stagingPath -Recurse -Force -WhatIf:$false -ErrorAction SilentlyContinue } }
}

function UpdateYtDlp {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory = $true)] [string] $TargetPath)
    if (Test-IsElevated) { throw 'UpdateYtDlp must be run from an unelevated PowerShell process.' }
    $resolvedTargetPath = Resolve-CanonicalYtDlpTargetPath $TargetPath
    if (-not $WhatIfPreference -and -not $PSCmdlet.ShouldProcess($resolvedTargetPath, 'replace verified yt-dlp nightly')) {
        return [pscustomobject]@{ Updated = $false; Declined = $true }
    }
    if (-not $WhatIfPreference) { Restore-PendingYtDlpTransaction -TargetPath $resolvedTargetPath }
    $metadataStagingPath = New-SiblingPath $resolvedTargetPath 'metadata'
    [IO.Directory]::CreateDirectory($metadataStagingPath) | Out-Null
    try {
        $official = Get-OfficialNightlyAsset $metadataStagingPath
        if ($WhatIfPreference) {
            $PSCmdlet.ShouldProcess($resolvedTargetPath, 'replace verified yt-dlp nightly') | Out-Null
            return Invoke-YtDlpTransaction -TargetPath $resolvedTargetPath -AssetPath $official.AssetPath -ReleaseTag $official.ReleaseTag -ExpectedSha256 $official.ExpectedSha256 -WhatIf
        }
        return Invoke-YtDlpTransaction -TargetPath $resolvedTargetPath -AssetPath $official.AssetPath -ReleaseTag $official.ReleaseTag -ExpectedSha256 $official.ExpectedSha256 -Confirm:$false
    }
    finally { if (Test-Path -LiteralPath $metadataStagingPath) { Remove-Item -LiteralPath $metadataStagingPath -Recurse -Force -WhatIf:$false -ErrorAction SilentlyContinue } }
}

Export-ModuleMember -Function RepairSettings, UpdateYtDlp
