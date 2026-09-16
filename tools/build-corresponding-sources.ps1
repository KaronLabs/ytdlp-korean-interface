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
    param([Parameter(Mandatory)] [string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StreamSha256 {
    param([Parameter(Mandatory)] [IO.Stream] $Stream)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { [Convert]::ToHexString($hasher.ComputeHash($Stream)).ToLowerInvariant() }
    finally { $hasher.Dispose() }
}

function Test-Property {
    param([Parameter(Mandatory)] [object] $Value, [Parameter(Mandatory)] [string] $Name)
    $null -ne $Value.PSObject.Properties[$Name]
}

function Assert-RelativePath {
    param([string] $Path, [Parameter(Mandatory)] [string] $ErrorId)
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
    if (-not $path.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw $ErrorId }
    $path
}

function Assert-JsonKeys {
    param([Text.Json.JsonElement] $Element, [string] $ErrorId)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw $ErrorId }
            Assert-JsonKeys $property.Value $ErrorId
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-JsonKeys $item $ErrorId }
    }
}

function Read-JsonFile {
    param([string] $Path, [string] $ErrorId)
    try {
        $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
        $document = [Text.Json.JsonDocument]::Parse($raw)
        try { Assert-JsonKeys $document.RootElement ($ErrorId + '_duplicate_key') }
        finally { $document.Dispose() }
        ConvertFrom-Json -InputObject $raw -Depth 64
    }
    catch {
        if ($_.Exception.Message.StartsWith($ErrorId, [StringComparison]::Ordinal)) { throw }
        throw $ErrorId
    }
}

function Assert-LicenseExpression {
    param([string] $Expression, [string] $ErrorId)
    if ([string]::IsNullOrWhiteSpace($Expression) -or $Expression -notmatch '^[A-Za-z0-9.+()\-\s]+$' -or
        $Expression -match '(?i)\b(?:NOASSERTION|NONE|NOT_VERIFIED|UNKNOWN|TODO)\b') { throw $ErrorId }
}

function Assert-PinnedUrl {
    param([string] $Url, [string] $Commit, [string] $ErrorId)
    $uri = $null
    if ($Commit -notmatch '^[a-fA-F0-9]{40}$' -or
        -not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -cne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
        -not $uri.AbsolutePath.EndsWith("/$Commit.zip", [StringComparison]::OrdinalIgnoreCase)) { throw $ErrorId }
    $uri.AbsoluteUri
}

function Assert-Notice {
    param([string] $Path, [string] $ExpectedSha256, [string] $ErrorPrefix)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or $ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        (Get-Sha256 $Path) -cne $ExpectedSha256.ToLowerInvariant()) { throw ($ErrorPrefix + '_notice_invalid') }
    $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    if ($text -match '(?i)\b(?:NOT_VERIFIED|UNKNOWN|TODO)\b|\bunresolved[\s_-]+blocker\b|\bblocker\s*:') {
        throw ($ErrorPrefix + '_notice_unresolved_marker')
    }
    $text
}

function Get-CandidateFiles {
    param([string] $Root)
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'source_candidate_reparse_point' }
        if ($item.PSIsContainer) { Get-CandidateFiles $item.FullName } else { $item }
    }
}

function Assert-ArchiveEntryPath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\\:\x00-\x1f<>"|?*]' -or $Path.StartsWith('/')) {
        throw "source_archive_entry_unsafe: $Path"
    }
    foreach ($part in $Path.TrimEnd('/').Split('/')) {
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
                if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw "source_archive_symlink_rejected: $($entry.FullName)" }
            }
            if ($seen.Count -eq 0) { throw 'source_archive_empty' }
        }
        finally { $zip.Dispose() }
    }
    catch [IO.InvalidDataException] { throw 'source_archive_invalid_zip' }
    finally { $stream.Dispose() }
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

function Assert-OutputZip {
    param([string] $Path, [Collections.Generic.Dictionary[string, object]] $Expected)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $zip.Entries) {
                Assert-ArchiveEntryPath $entry.FullName
                if (-not $seen.Add($entry.FullName)) { throw 'source_output_entry_duplicate' }
                if (-not $Expected.ContainsKey($entry.FullName)) { throw 'source_output_inventory_mismatch' }
                $entryStream = $entry.Open()
                try { $actual = Get-StreamSha256 $entryStream } finally { $entryStream.Dispose() }
                if ($actual -cne [string]$Expected[$entry.FullName].sha256) { throw 'source_output_hash_mismatch' }
            }
            if ($seen.Count -ne $Expected.Count) { throw 'source_output_inventory_mismatch' }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }
}

$lockFile = (Resolve-Path -LiteralPath $LockPath).Path
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$candidate = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\', '/')
$cache = (Resolve-Path -LiteralPath $CacheDirectory).Path
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$lock = Read-JsonFile $lockFile 'source_lock_invalid'

if ($lock.schemaVersion -cne 'karon-license-lock/v2' -or $lock.release.tag -cne 'v2.19.1-karon.2' -or
    $lock.release.platform -cne 'win-x64') { throw 'source_lock_invalid' }
if (-not (Test-Property $lock.release 'verificationStatus')) { throw 'source_release_status_missing' }
if ($lock.release.verificationStatus -cne 'verified') { throw 'source_release_not_verified' }
if (-not (Test-Property $lock.release 'blockers')) { throw 'source_release_blockers_missing' }
if (@($lock.release.blockers).Count -ne 0) { throw 'source_release_blocked' }

if (-not (Test-Property $lock.release 'metadataPackage')) { throw 'source_release_metadata_missing' }
$metadataPackage = $lock.release.metadataPackage
if ($metadataPackage.id -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') { throw 'source_release_metadata_invalid' }
Assert-LicenseExpression ([string]$metadataPackage.licenseExpression) 'source_license_unverified'
Assert-LicenseExpression ([string]$metadataPackage.licenseConcluded) 'source_license_unverified'
[void](Assert-PinnedUrl ([string]$metadataPackage.downloadLocation) ([string]$metadataPackage.sourceCommit) 'source_url_unpinned')

$componentById = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$noticePaths = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$archiveRequests = [Collections.Generic.List[object]]::new()
$licenseRefIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$expressions = [Collections.Generic.List[string]]::new()
$expressions.Add([string]$metadataPackage.licenseExpression)
$expressions.Add([string]$metadataPackage.licenseConcluded)

foreach ($component in @($lock.components)) {
    if ($component.id -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$' -or -not $componentById.TryAdd([string]$component.id, $component)) {
        throw 'source_component_invalid'
    }
    if (-not (Test-Property $component 'verificationStatus')) { throw 'source_component_status_missing' }
    if ($component.verificationStatus -cne 'verified') { throw 'source_component_not_verified' }
    if (-not (Test-Property $component 'blockers')) { throw 'source_component_blockers_missing' }
    if (@($component.blockers).Count -ne 0) { throw 'source_component_blocked' }
    Assert-LicenseExpression ([string]$component.licenseExpression) 'source_license_unverified'
    Assert-LicenseExpression ([string]$component.licenseConcluded) 'source_license_unverified'
    $expressions.Add([string]$component.licenseExpression)
    $expressions.Add([string]$component.licenseConcluded)
    if ($component.modified -isnot [bool] -or $component.filesAnalyzed -isnot [bool] -or
        [string]::IsNullOrWhiteSpace([string]$component.buildRecipe) -or
        @($component.noticeFiles).Count -eq 0 -or @($component.sourceArchives).Count -eq 0) {
        throw 'source_component_metadata_incomplete'
    }

    foreach ($notice in @($component.noticeFiles)) {
        $relative = [string]$notice.path
        $noticePath = Get-ChildPath $source $relative 'source_notice_path_invalid'
        $text = Assert-Notice $noticePath ([string]$notice.sha256) 'source'
        if ($noticePaths.ContainsKey($relative)) {
            if ($noticePaths[$relative].sha256 -cne ([string]$notice.sha256).ToLowerInvariant()) { throw 'source_notice_hash_conflict' }
        }
        else { $noticePaths.Add($relative, [pscustomobject]@{ path = $noticePath; sha256 = ([string]$notice.sha256).ToLowerInvariant(); text = $text }) }
    }

    $hasPrimarySource = $false
    foreach ($archive in @($component.sourceArchives)) {
        Assert-RelativePath ([string]$archive.fileName) 'source_archive_name_invalid'
        if ([string]$archive.fileName -notmatch '^[^/]+\.zip$' -or $archive.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            -not (Test-Property $archive 'commit')) { throw 'source_archive_metadata_invalid' }
        $archiveUrl = Assert-PinnedUrl ([string]$archive.url) ([string]$archive.commit) 'source_url_unpinned'
        if ([string]$archive.commit -ceq [string]$component.sourceCommit) { $hasPrimarySource = $true }
        $archiveRequests.Add([pscustomobject]@{
            component = [string]$component.id
            fileName = [string]$archive.fileName
            url = $archiveUrl
            sha256 = ([string]$archive.sha256).ToLowerInvariant()
        })
    }
    if (-not $hasPrimarySource) { throw 'source_primary_archive_missing' }

    $componentLicenseRefs = if (Test-Property $component 'licenseRefs') { @($component.licenseRefs) } else { @() }
    foreach ($licenseRef in $componentLicenseRefs) {
        if ($licenseRef.licenseId -notmatch '^LicenseRef-[A-Za-z0-9.-]+$' -or -not $licenseRefIds.Add([string]$licenseRef.licenseId) -or
            -not $noticePaths.ContainsKey([string]$licenseRef.noticePath) -or [string]::IsNullOrWhiteSpace([string]$licenseRef.name)) {
            throw 'source_license_ref_invalid'
        }
    }
}
if ($componentById.Count -eq 0 -or $componentById.ContainsKey([string]$metadataPackage.id)) { throw 'source_component_invalid' }

$inventory = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$packageCounts = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
$packageCounts.Add([string]$metadataPackage.id, 0)
foreach ($componentId in $componentById.Keys) { $packageCounts.Add($componentId, 0) }
foreach ($entry in @($lock.release.candidateFiles)) {
    $relative = [string]$entry.path
    Assert-RelativePath $relative 'source_candidate_inventory_invalid'
    Assert-LicenseExpression ([string]$entry.licenseConcluded) 'source_license_unverified'
    $expressions.Add([string]$entry.licenseConcluded)
    if ($entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or -not $packageCounts.ContainsKey([string]$entry.package) -or
        -not $inventory.TryAdd($relative, $entry)) {
        if (-not $packageCounts.ContainsKey([string]$entry.package)) { throw 'source_candidate_package_unknown' }
        throw 'source_candidate_inventory_duplicate'
    }
    $packageCounts[[string]$entry.package]++
}
if ($inventory.Count -eq 0 -or -not $inventory.ContainsKey('candidate-manifest.json')) { throw 'source_candidate_inventory_missing' }
if ([string]$inventory['candidate-manifest.json'].path -cne 'candidate-manifest.json' -or
    [string]$inventory['candidate-manifest.json'].package -cne [string]$metadataPackage.id) { throw 'source_candidate_manifest_inventory_mismatch' }

$actualPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @(Get-CandidateFiles $candidate)) {
    $relative = [IO.Path]::GetRelativePath($candidate, $file.FullName).Replace('\', '/')
    if (-not $actualPaths.Add($relative)) { throw 'source_candidate_inventory_duplicate' }
    if (-not $inventory.ContainsKey($relative)) { throw "source_candidate_inventory_extra: $relative" }
    if ((Get-Sha256 $file.FullName) -cne ([string]$inventory[$relative].sha256).ToLowerInvariant()) {
        throw "source_candidate_hash_mismatch: $relative"
    }
}
if ($actualPaths.Count -ne $inventory.Count) { throw 'source_candidate_inventory_missing' }

foreach ($component in $componentById.Values) {
    $count = $packageCounts[[string]$component.id]
    if ($component.filesAnalyzed) {
        if ($count -eq 0) { throw 'source_candidate_package_empty' }
    }
    else {
        if ($count -ne 0 -or -not (Test-Property $component 'staticLinkTarget') -or
            -not $componentById.ContainsKey([string]$component.staticLinkTarget) -or
            -not $componentById[[string]$component.staticLinkTarget].filesAnalyzed) { throw 'source_static_link_invalid' }
    }
}
if ($packageCounts[[string]$metadataPackage.id] -ne 1) { throw 'source_release_metadata_inventory_invalid' }

$manifestPath = Get-ChildPath $candidate 'candidate-manifest.json' 'source_candidate_manifest_invalid'
$manifest = Read-JsonFile $manifestPath 'source_candidate_manifest_invalid'
if ($manifest.schemaVersion -ne 1 -or -not (Test-Property $manifest 'files')) { throw 'source_candidate_manifest_invalid' }
$manifestFiles = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($manifest.files)) {
    $relative = [string]$entry.path
    Assert-RelativePath $relative 'source_candidate_manifest_inventory_mismatch'
    if ($relative -ieq 'candidate-manifest.json' -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        ([string]$entry.length) -notmatch '^(0|[1-9][0-9]*)$') { throw 'source_candidate_manifest_inventory_mismatch' }
    if (-not $manifestFiles.TryAdd($relative, $entry)) { throw 'source_candidate_manifest_duplicate' }
}
if ($manifestFiles.Count -ne ($inventory.Count - 1)) { throw 'source_candidate_manifest_inventory_mismatch' }
foreach ($relative in $inventory.Keys) {
    if ($relative -ieq 'candidate-manifest.json') { continue }
    if (-not $manifestFiles.ContainsKey($relative)) { throw 'source_candidate_manifest_inventory_mismatch' }
    $manifestEntry = $manifestFiles[$relative]
    if ([string]$manifestEntry.sha256 -cne [string]$inventory[$relative].sha256) { throw "source_candidate_manifest_hash_mismatch: $relative" }
    $candidatePath = Get-ChildPath $candidate $relative 'source_candidate_manifest_inventory_mismatch'
    if ([long]$manifestEntry.length -ne (Get-Item -LiteralPath $candidatePath).Length) { throw "source_candidate_manifest_inventory_mismatch: $relative" }
}

foreach ($expression in $expressions) {
    foreach ($match in [regex]::Matches($expression, 'LicenseRef-[A-Za-z0-9.-]+')) {
        if (-not $licenseRefIds.Contains($match.Value)) { throw "source_license_ref_missing: $($match.Value)" }
    }
}

$rootNotice = Join-Path $source 'THIRD-PARTY-NOTICES.txt'
if (-not (Test-Path -LiteralPath $rootNotice -PathType Leaf)) { throw 'source_root_notice_missing' }
$rootNoticeText = [IO.File]::ReadAllText($rootNotice, [Text.UTF8Encoding]::new($false, $true))
if ($rootNoticeText -match '(?i)\b(?:NOT_VERIFIED|UNKNOWN|TODO)\b|\bunresolved[\s_-]+blocker\b|\bblocker\s*:') {
    throw 'source_notice_unresolved_marker'
}

$resolvedArchives = [Collections.Generic.List[object]]::new()
$cacheContracts = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($archive in $archiveRequests) {
    if ($cacheContracts.ContainsKey($archive.fileName)) {
        $existing = $cacheContracts[$archive.fileName]
        if ($existing.sha256 -cne $archive.sha256 -or $existing.url -cne $archive.url) { throw 'source_archive_cache_conflict' }
    }
    else { $cacheContracts.Add($archive.fileName, $archive) }

    $cachePath = Join-Path $cache $archive.fileName
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        $downloadPartial = "$cachePath.$PID.$([Guid]::NewGuid().ToString('N')).partial"
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $archive.url -OutFile $downloadPartial
            if ((Get-Sha256 $downloadPartial) -cne $archive.sha256) { throw 'source_archive_hash_mismatch' }
            [IO.File]::Move($downloadPartial, $cachePath, $false)
        }
        finally {
            if (Test-Path -LiteralPath $downloadPartial) { Remove-Item -LiteralPath $downloadPartial -Force }
        }
    }
    if ((Get-Sha256 $cachePath) -cne $archive.sha256) { throw 'source_archive_hash_mismatch' }
    Assert-SafeZip $cachePath
    $resolvedArchives.Add([pscustomobject]@{ component = $archive.component; fileName = $archive.fileName; path = $cachePath; sha256 = $archive.sha256 })
}

$bundleName = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources'
$expectedEntries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-BundleInput {
    param([string] $EntryName, [string] $Path, [string] $Sha256)
    Assert-ArchiveEntryPath $EntryName
    if (-not $expectedEntries.TryAdd($EntryName, [pscustomobject]@{ path = $Path; sha256 = $Sha256 })) { throw 'source_output_entry_duplicate' }
}

Add-BundleInput "$bundleName/release/dependencies/v2.19.1-karon.2.lock.json" $lockFile (Get-Sha256 $lockFile)
Add-BundleInput "$bundleName/THIRD-PARTY-NOTICES.txt" $rootNotice (Get-Sha256 $rootNotice)
foreach ($relative in $noticePaths.Keys) {
    Add-BundleInput "$bundleName/$relative" $noticePaths[$relative].path $noticePaths[$relative].sha256
}
foreach ($archive in $resolvedArchives) {
    Add-BundleInput "$bundleName/sources/$($archive.component)/$($archive.fileName)" $archive.path $archive.sha256
}

$outputPath = Join-Path $outputRoot ($bundleName + '.zip')
if (Test-Path -LiteralPath $outputPath) { throw 'source_output_exists' }
$partialPath = "$outputPath.$PID.$([Guid]::NewGuid().ToString('N')).partial"
try {
    $stream = [IO.File]::Open($partialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($entryName in @($expectedEntries.Keys | Sort-Object)) {
                Add-ZipFile $zip $entryName $expectedEntries[$entryName].path
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }

    Assert-OutputZip $partialPath $expectedEntries
    [IO.File]::Move($partialPath, $outputPath, $false)
}
catch {
    if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force }
    throw
}
finally {
    if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force }
}

Write-Output $outputPath
