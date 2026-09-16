#requires -Version 7.4

[CmdletBinding()]
param(
    [string] $LockPath = (Join-Path $PSScriptRoot '..\release\dependencies\v2.19.1-karon.2.lock.json'),
    [string] $SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)] [string] $CandidateRoot,
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
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\\:\x00-\x1f<>"|?*]' -or $Path.StartsWith('/')) {
        throw $ErrorId
    }
    foreach ($part in $Path.Split('/')) {
        if ($part -in @('', '.', '..') -or $part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') {
            throw $ErrorId
        }
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
            if (-not $names.Add($property.Name)) { throw 'spdx_duplicate_lock_key' }
        }
    }
    finally { $document.Dispose() }
    ConvertFrom-Json -InputObject $raw -Depth 64
}

function Assert-HttpsPinnedSource {
    param([object] $Archive, [string] $Commit)
    $archiveCommit = if ($null -ne $Archive.PSObject.Properties['commit']) { [string]$Archive.commit } else { $Commit }
    if ($Archive.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'spdx_source_hash_invalid' }
    $uri = $null
    if (-not [Uri]::TryCreate([string]$Archive.url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -cne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
        $archiveCommit -notmatch '^[a-fA-F0-9]{40}$' -or -not $uri.AbsoluteUri.Contains($archiveCommit, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'spdx_source_url_unpinned'
    }
}

function Get-CandidateFiles {
    param([string] $Root)
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'spdx_candidate_reparse_point' }
        if ($item.PSIsContainer) { Get-CandidateFiles $item.FullName }
        else { $item }
    }
}

$lockFile = (Resolve-Path -LiteralPath $LockPath).Path
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$candidate = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\', '/')
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$lock = Read-LockFile $lockFile
if ($lock.schemaVersion -cne 'karon-license-lock/v1' -or $lock.release.tag -cne 'v2.19.1-karon.2' -or
    $lock.release.platform -cne 'win-x64') { throw 'spdx_lock_invalid' }
if ($null -ne $lock.release.PSObject.Properties['verificationStatus'] -and
    $lock.release.verificationStatus -cne 'verified') { throw 'spdx_release_not_verified' }

$expected = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$assignments = [Collections.Generic.Dictionary[string, Collections.Generic.List[string]]]::new([StringComparer]::OrdinalIgnoreCase)
$packages = [Collections.Generic.List[object]]::new()
$relationships = [Collections.Generic.List[object]]::new()

foreach ($component in @($lock.components)) {
    if ($component.id -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') { throw 'spdx_component_invalid' }
    if ($component.verificationStatus -cne 'verified') { throw 'spdx_component_not_verified' }
    if ([string]::IsNullOrWhiteSpace([string]$component.licenseExpression) -or
        $component.licenseExpression -match '(?i)NOASSERTION|NOT_VERIFIED|UNKNOWN') { throw 'spdx_license_unverified' }
    if (@($component.noticeFiles).Count -eq 0 -or @($component.sourceArchives).Count -eq 0) {
        throw 'spdx_notice_or_source_missing'
    }
    if ([string]::IsNullOrWhiteSpace([string]$component.buildRecipe)) { throw 'spdx_build_recipe_missing' }
    foreach ($notice in @($component.noticeFiles)) {
        $noticePath = Get-ChildPath $source ([string]$notice.path) 'spdx_notice_path_invalid'
        if (-not (Test-Path -LiteralPath $noticePath -PathType Leaf)) { throw 'spdx_notice_or_source_missing' }
        if ($notice.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-Sha256 $noticePath) -cne $notice.sha256.ToLowerInvariant()) {
            throw 'spdx_notice_hash_mismatch'
        }
    }
    foreach ($archive in @($component.sourceArchives)) { Assert-HttpsPinnedSource $archive ([string]$component.sourceCommit) }
    foreach ($binary in @($component.binaryFiles)) {
        Assert-RelativePath ([string]$binary.path) 'spdx_candidate_path_invalid'
        if ($binary.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'spdx_candidate_hash_invalid' }
        $path = [string]$binary.path
        $sha = $binary.sha256.ToLowerInvariant()
        if ($expected.ContainsKey($path) -and $expected[$path] -cne $sha) { throw 'spdx_candidate_hash_conflict' }
        $expected[$path] = $sha
        if (-not $assignments.ContainsKey($path)) {
            $assignments[$path] = [Collections.Generic.List[string]]::new()
        }
        $assignments[$path].Add([string]$component.id)
    }
    $packageId = 'SPDXRef-Package-' + $component.id
    $packages.Add([ordered]@{
        name = [string]$component.name
        SPDXID = $packageId
        versionInfo = [string]$component.version
        downloadLocation = [string]$component.sourceRepository
        filesAnalyzed = $true
        licenseConcluded = [string]$component.licenseExpression
        licenseDeclared = [string]$component.licenseExpression
        copyrightText = 'See the component notice files recorded by the release lock.'
    })
    $relationships.Add([ordered]@{ spdxElementId = 'SPDXRef-DOCUMENT'; relationshipType = 'DESCRIBES'; relatedSpdxElement = $packageId })
}

$candidateFiles = @(Get-CandidateFiles $candidate)
if ($candidateFiles.Count -eq 0) { throw 'spdx_candidate_empty' }
$files = [Collections.Generic.List[object]]::new()
foreach ($file in $candidateFiles) {
    $relative = [IO.Path]::GetRelativePath($candidate, $file.FullName).Replace('\', '/')
    if (-not $assignments.ContainsKey($relative)) { throw "spdx_unknown_candidate_file: $relative" }
    $actual = Get-Sha256 $file.FullName
    if ($actual -cne $expected[$relative]) { throw "spdx_candidate_hash_mismatch: $relative" }
    $pathDigest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($relative))).ToLowerInvariant()
    $fileId = 'SPDXRef-File-' + $pathDigest.Substring(0, 20)
    $primary = @($lock.components | Where-Object { $_.id -ceq $assignments[$relative][0] })[0]
    $files.Add([ordered]@{
        fileName = './' + $relative
        SPDXID = $fileId
        checksums = @([ordered]@{ algorithm = 'SHA256'; checksumValue = $actual })
        licenseConcluded = [string]$primary.licenseExpression
        copyrightText = 'See the assigned component notice files.'
    })
    foreach ($componentId in $assignments[$relative]) {
        $relationships.Add([ordered]@{ spdxElementId = 'SPDXRef-Package-' + $componentId; relationshipType = 'CONTAINS'; relatedSpdxElement = $fileId })
    }
}
foreach ($path in $expected.Keys) {
    if (-not (Test-Path -LiteralPath (Get-ChildPath $candidate $path 'spdx_candidate_path_invalid') -PathType Leaf)) {
        throw "spdx_candidate_file_missing: $path"
    }
}

$outputPath = Join-Path $outputRoot 'ytdlp-korean-interface-v2.19.1-karon.2.spdx.json'
if (Test-Path -LiteralPath $outputPath) { throw 'spdx_output_exists' }
$lockHash = Get-Sha256 $lockFile
$document = [ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = 'ytdlp-korean-interface-v2.19.1-karon.2-win-x64'
    documentNamespace = "https://github.com/KaronLabs/ytdlp-korean-interface/spdx/v2.19.1-karon.2/$lockHash"
    creationInfo = [ordered]@{
        created = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        creators = @('Organization: KaronLabs', 'Tool: generate-release-spdx.ps1')
        licenseListVersion = '3.27'
    }
    packages = @($packages)
    files = @($files)
    relationships = @($relationships)
}
$json = $document | ConvertTo-Json -Depth 16
[IO.File]::WriteAllText($outputPath, $json + "`n", [Text.UTF8Encoding]::new($false))
Write-Output $outputPath
