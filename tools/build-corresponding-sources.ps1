#requires -Version 7.4

[CmdletBinding()]
param(
    [string] $LockPath = (Join-Path $PSScriptRoot '..\release\dependencies\v2.19.1-karon.2.lock.json'),
    [string] $SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)] [string] $CandidateRoot,
    [Parameter(Mandatory)] [string] $CacheDirectory,
    [Parameter(Mandatory)] [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256 {
    param([string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-RelativePath {
    param([string] $Path, [string] $ErrorId)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\\:\x00-\x1f<>"|?*]' -or $Path.StartsWith('/')) { throw $ErrorId }
    foreach ($part in $Path.Split('/')) {
        if ($part -in @('', '.', '..') -or $part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') { throw $ErrorId }
    }
}

function Get-ChildPath {
    param([string] $Root, [string] $Relative, [string] $ErrorId)
    Assert-RelativePath $Relative $ErrorId
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $path = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
    if (-not $path.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw $ErrorId }
    $path
}

function Read-LockFile {
    param([string] $Path)
    $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    $document = [Text.Json.JsonDocument]::Parse($raw)
    try {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $document.RootElement.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'source_duplicate_lock_key' }
        }
    }
    finally { $document.Dispose() }
    ConvertFrom-Json -InputObject $raw -Depth 64
}

function Assert-ArchiveEntryPath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\\:\x00-\x1f<>"|?*]' -or $Path.StartsWith('/')) {
        throw "source_archive_entry_unsafe: $Path"
    }
    $parts = @($Path.TrimEnd('/').Split('/'))
    foreach ($part in $parts) {
        if ($part -in @('', '.', '..') -or $part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') {
            throw "source_archive_entry_unsafe: $Path"
        }
    }
}

function Assert-SafeZip {
    param([string] $Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $zip.Entries) {
                Assert-ArchiveEntryPath $entry.FullName
                if (-not $seen.Add($entry.FullName)) { throw "source_archive_entry_duplicate: $($entry.FullName)" }
                $unixType = ($entry.ExternalAttributes -shr 16) -band 0xF000
                if ($unixType -eq 0xA000) { throw "source_archive_symlink_rejected: $($entry.FullName)" }
            }
            if ($seen.Count -eq 0) { throw 'source_archive_empty' }
        }
        finally { $zip.Dispose() }
    }
    catch [IO.InvalidDataException] { throw 'source_archive_invalid_zip' }
    finally { $stream.Dispose() }
}

function Get-CandidateFiles {
    param([string] $Root)
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'source_candidate_reparse_point' }
        if ($item.PSIsContainer) { Get-CandidateFiles $item.FullName }
        else { $item }
    }
}

function Add-ZipFile {
    param([IO.Compression.ZipArchive] $Zip, [string] $EntryName, [string] $Path)
    Assert-ArchiveEntryPath $EntryName
    $entry = $Zip.CreateEntry($EntryName, [IO.Compression.CompressionLevel]::Optimal)
    $input = [IO.File]::OpenRead($Path)
    try {
        $output = $entry.Open()
        try { $input.CopyTo($output) } finally { $output.Dispose() }
    }
    finally { $input.Dispose() }
}

$lockFile = (Resolve-Path -LiteralPath $LockPath).Path
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$candidate = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\', '/')
$cache = (Resolve-Path -LiteralPath $CacheDirectory).Path
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$lock = Read-LockFile $lockFile
if ($lock.schemaVersion -cne 'karon-license-lock/v1' -or $lock.release.tag -cne 'v2.19.1-karon.2' -or
    $lock.release.platform -cne 'win-x64') { throw 'source_lock_invalid' }
if ($null -ne $lock.release.PSObject.Properties['verificationStatus'] -and
    $lock.release.verificationStatus -cne 'verified') { throw 'source_release_not_verified' }

$expected = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$archives = [Collections.Generic.List[object]]::new()
$noticePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($component in @($lock.components)) {
    if ($component.id -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$' -or $component.verificationStatus -cne 'verified') {
        throw 'source_component_not_verified'
    }
    if ($component.licenseExpression -match '(?i)NOASSERTION|NOT_VERIFIED|UNKNOWN' -or
        @($component.noticeFiles).Count -eq 0 -or @($component.sourceArchives).Count -eq 0 -or
        [string]::IsNullOrWhiteSpace([string]$component.buildRecipe)) { throw 'source_component_metadata_incomplete' }
    foreach ($notice in @($component.noticeFiles)) {
        $noticePath = Get-ChildPath $source ([string]$notice.path) 'source_notice_path_invalid'
        if (-not (Test-Path -LiteralPath $noticePath -PathType Leaf) -or $notice.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            (Get-Sha256 $noticePath) -cne $notice.sha256.ToLowerInvariant()) { throw 'source_notice_invalid' }
        [void]$noticePaths.Add([string]$notice.path)
    }
    foreach ($binary in @($component.binaryFiles)) {
        Assert-RelativePath ([string]$binary.path) 'source_candidate_path_invalid'
        if ($binary.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'source_candidate_hash_invalid' }
        $sha = $binary.sha256.ToLowerInvariant()
        if ($expected.ContainsKey([string]$binary.path) -and $expected[[string]$binary.path] -cne $sha) {
            throw 'source_candidate_hash_conflict'
        }
        $expected[[string]$binary.path] = $sha
    }
    foreach ($archive in @($component.sourceArchives)) {
        $archiveCommit = if ($null -ne $archive.PSObject.Properties['commit']) { [string]$archive.commit } else { [string]$component.sourceCommit }
        Assert-RelativePath ([string]$archive.fileName) 'source_archive_name_invalid'
        if ([string]$archive.fileName -notmatch '\.zip$' -or $archive.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            $archiveCommit -notmatch '^[a-fA-F0-9]{40}$') { throw 'source_archive_metadata_invalid' }
        $uri = $null
        if (-not [Uri]::TryCreate([string]$archive.url, [UriKind]::Absolute, [ref]$uri) -or
            $uri.Scheme -cne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
            -not $uri.AbsoluteUri.Contains($archiveCommit, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'source_url_unpinned'
        }
        $cachePath = Join-Path $cache ([string]$archive.fileName)
        if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
            $partial = $cachePath + '.partial'
            Invoke-WebRequest -UseBasicParsing -Uri $uri.AbsoluteUri -OutFile $partial
            if ((Get-Sha256 $partial) -cne $archive.sha256.ToLowerInvariant()) {
                Remove-Item -LiteralPath $partial -Force
                throw 'source_archive_hash_mismatch'
            }
            Move-Item -LiteralPath $partial -Destination $cachePath
        }
        if ((Get-Sha256 $cachePath) -cne $archive.sha256.ToLowerInvariant()) { throw 'source_archive_hash_mismatch' }
        Assert-SafeZip $cachePath
        $archives.Add([pscustomobject]@{ component = [string]$component.id; fileName = [string]$archive.fileName; path = $cachePath })
    }
}

$seenCandidate = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @(Get-CandidateFiles $candidate)) {
    $relative = [IO.Path]::GetRelativePath($candidate, $file.FullName).Replace('\', '/')
    if (-not $expected.ContainsKey($relative)) { throw "source_unknown_candidate_file: $relative" }
    if ((Get-Sha256 $file.FullName) -cne $expected[$relative]) { throw "source_candidate_hash_mismatch: $relative" }
    [void]$seenCandidate.Add($relative)
}
if ($seenCandidate.Count -ne $expected.Count) { throw 'source_candidate_file_missing' }

$bundleName = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources'
$outputPath = Join-Path $outputRoot ($bundleName + '.zip')
if (Test-Path -LiteralPath $outputPath) { throw 'source_output_exists' }
$output = [IO.File]::Open($outputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $zip = [IO.Compression.ZipArchive]::new($output, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        Add-ZipFile $zip "$bundleName/release/dependencies/v2.19.1-karon.2.lock.json" $lockFile
        $rootNotice = Join-Path $source 'THIRD-PARTY-NOTICES.txt'
        if (-not (Test-Path -LiteralPath $rootNotice -PathType Leaf)) { throw 'source_root_notice_missing' }
        Add-ZipFile $zip "$bundleName/THIRD-PARTY-NOTICES.txt" $rootNotice
        foreach ($notice in $noticePaths) {
            Add-ZipFile $zip "$bundleName/$notice" (Get-ChildPath $source $notice 'source_notice_path_invalid')
        }
        foreach ($archive in $archives) {
            Add-ZipFile $zip "$bundleName/sources/$($archive.component)/$($archive.fileName)" $archive.path
        }
    }
    finally { $zip.Dispose() }
}
finally { $output.Dispose() }
Write-Output $outputPath
