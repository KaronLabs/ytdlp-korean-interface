[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FirstReleaseConfiguration {
    return [pscustomobject]@{
        Tag = 'v2.19.1-karon.1'
        Title = 'ytdlp-korean-interface v2.19.1-karon.1'
        Repository = 'KaronLabs/ytdlp-korean-interface'
        UpstreamRepository = 'ErrorFlynn/ytdlp-interface'
        UpstreamTag = 'v2.19.1'
        UpstreamCommit = '2173316ebb5e50af49a2a4e939693fa8c3a3459c'
        UpstreamAssetName = 'ytdlp-interface.7z'
        UpstreamArchiveSha256 = '53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e'
        Platform = 'win-x64'
        PackageName = 'ytdlp-korean-interface-v2.19.1-karon.1-win-x64'
        ZipName = 'ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip'
        ChecksumName = 'SHA256SUMS.txt'
    }
}

function Test-HexDigest {
    param([string] $Value, [int] $Length = 64)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value -match ('^[0-9a-fA-F]{' + $Length + '}$')
}

function Test-SafeReleaseRelativePath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path)) { return $false }
    $normalized = $Path.Replace('\', '/')
    if ($normalized.StartsWith('/') -or $normalized.Contains("`0")) { return $false }
    $parts = @($normalized -split '/')
    if ($parts.Count -eq 0 -or @($parts | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -ne 0) { return $false }
    foreach ($part in $parts) {
        if ($part -ieq '.git' -or $part -ieq '.vs' -or $part -ieq 'Debug' -or $part -ieq 'Release' -or
            $part -ieq 'candidate-runtime' -or $part -ieq 'smoke-evidence' -or $part -ieq 'provenance-staging') { return $false }
    }
    return $true
}

function Read-ReleaseRequest {
    param([Parameter(Mandatory = $true)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'release_request_missing' }
    try { $request = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'release_request_invalid' }
    $null = Assert-ReleaseRequest -Request $request
    return $request
}

function Assert-ReleaseRequest {
    param([Parameter(Mandatory = $true)] [object] $Request)
    $config = Get-FirstReleaseConfiguration
    $expectedNames = @('schemaVersion','tag','platform','upstreamRepository','upstreamTag','upstreamCommit','upstreamAsset','upstreamArchiveSha256')
    $actualNames = @($Request.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
    $sortedExpected = @($expectedNames | Sort-Object)
    if ($actualNames.Count -ne $sortedExpected.Count) { throw 'release_request_invalid' }
    for ($i = 0; $i -lt $actualNames.Count; $i++) {
        if ($actualNames[$i] -cne $sortedExpected[$i]) { throw 'release_request_invalid' }
    }
    if ($Request.schemaVersion -ne 1 -or
        [string]$Request.tag -cne $config.Tag -or
        [string]$Request.platform -cne $config.Platform -or
        [string]$Request.upstreamRepository -cne $config.UpstreamRepository -or
        [string]$Request.upstreamTag -cne $config.UpstreamTag -or
        [string]$Request.upstreamCommit -cne $config.UpstreamCommit -or
        [string]$Request.upstreamAsset -cne $config.UpstreamAssetName -or
        ([string]$Request.upstreamArchiveSha256).ToLowerInvariant() -cne $config.UpstreamArchiveSha256.ToLowerInvariant()) {
        throw 'release_request_invalid'
    }
    return $true
}

function Invoke-ReleaseGit {
    param([Parameter(Mandatory = $true)] [string[]] $Arguments, [string] $WorkingDirectory)
    $old = Get-Location
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { Set-Location -LiteralPath $WorkingDirectory }
        $output = @(& git @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) { throw ('release_git_failed: git ' + ($Arguments -join ' ') + ' :: ' + (($output | Out-String).Trim())) }
        return $output
    }
    finally { Set-Location -LiteralPath $old }
}

function Assert-ReleaseSourceRevision {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot, [Parameter(Mandatory = $true)] [string] $ExpectedSha)
    if (-not (Test-HexDigest -Value $ExpectedSha -Length 40)) { throw 'release_source_invalid' }
    $head = ((Invoke-ReleaseGit -Arguments @('rev-parse','--verify','HEAD^{commit}') -WorkingDirectory $SourceRoot) | Out-String).Trim().ToLowerInvariant()
    if ($head -cne $ExpectedSha.ToLowerInvariant()) { throw 'release_source_mismatch' }
    $status = ((Invoke-ReleaseGit -Arguments @('status','--porcelain=v1') -WorkingDirectory $SourceRoot) | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($status)) { throw 'release_source_dirty' }
    return $head
}

function Assert-UpstreamArchiveHash {
    param([Parameter(Mandatory = $true)] [string] $ArchivePath)
    $config = Get-FirstReleaseConfiguration
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf) -or (Split-Path -Leaf $ArchivePath) -cne $config.UpstreamAssetName) {
        throw 'upstream_archive_invalid'
    }
    $actual = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $config.UpstreamArchiveSha256.ToLowerInvariant()) { throw 'upstream_archive_hash_mismatch' }
    return $actual
}

function Get-UpstreamRuntimeRequiredFiles {
    # ErrorFlynn v2.19.1 x64 release ships these six runtime files at archive root.
    # ytdlp-interface.json is intentionally generated by the KaronLabs release bootstrap.
    return @('ytdlp-interface.exe','yt-dlp.exe','ffmpeg.exe','ffprobe.exe','deno.exe','7z.dll')
}

function Test-UpstreamRuntimeComplete {
    param([Parameter(Mandatory = $true)] [string] $RuntimeRoot)
    foreach ($name in Get-UpstreamRuntimeRequiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot $name) -PathType Leaf)) { return $false }
    }
    return $true
}

function Resolve-UpstreamRuntimeRoot {
    param([Parameter(Mandatory = $true)] [string] $ExtractedRoot)
    if (-not (Test-Path -LiteralPath $ExtractedRoot -PathType Container)) { throw 'upstream_runtime_incomplete' }
    $root = [IO.Path]::GetFullPath($ExtractedRoot)
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'upstream_runtime_reparse_point' }
    }
    $candidateRoots = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (Test-UpstreamRuntimeComplete -RuntimeRoot $root) { $candidateRoots.Add($root) | Out-Null }
    foreach ($product in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'ytdlp-interface.exe' -Force)) {
        $parent = [IO.Path]::GetFullPath($product.DirectoryName)
        if (Test-UpstreamRuntimeComplete -RuntimeRoot $parent) { $candidateRoots.Add($parent) | Out-Null }
    }
    $resolved = @($candidateRoots)
    if ($resolved.Count -eq 0) { throw 'upstream_runtime_incomplete' }
    if ($resolved.Count -ne 1) { throw 'upstream_runtime_ambiguous' }
    return $resolved[0]
}

function Copy-ReleaseTree {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot, [Parameter(Mandatory = $true)] [string] $DestinationRoot)
    $source = [IO.Path]::GetFullPath($SourceRoot)
    foreach ($item in @(Get-ChildItem -LiteralPath $source -Recurse -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'release_package_reparse_point' }
        $relative = $item.FullName.Substring($source.Length).TrimStart('\','/').Replace('\','/')
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        if (-not (Test-SafeReleaseRelativePath -Path $relative)) { throw 'release_manifest_invalid' }
        $target = Join-Path $DestinationRoot $relative
        if ($item.PSIsContainer) { [IO.Directory]::CreateDirectory($target) | Out-Null }
        else {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}

function Get-ReleaseInventory {
    param([Parameter(Mandatory = $true)] [string] $PackageRoot)
    $root = [IO.Path]::GetFullPath($PackageRoot)
    $records = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Sort-Object FullName)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'release_package_reparse_point' }
        $relative = $file.FullName.Substring($root.Length).TrimStart('\','/').Replace('\','/')
        if ($relative -ceq 'release-manifest.json') { continue }
        if (-not (Test-SafeReleaseRelativePath -Path $relative)) { throw 'release_manifest_invalid' }
        $records += [ordered]@{
            path = $relative
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            length = [long]$file.Length
        }
    }
    return @($records)
}

function New-ReleasePackage {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $CandidateRoot,
        [Parameter(Mandatory = $true)] [string] $CandidateManifestSha256,
        [Parameter(Mandatory = $true)] [string] $SourceSha,
        [Parameter(Mandatory = $true)] [string] $SmokeEvidenceSha256,
        [Parameter(Mandatory = $true)] [string] $YtDlpTag,
        [Parameter(Mandatory = $true)] [string] $YtDlpSha256,
        [Parameter(Mandatory = $true)] [string] $OutputRoot
    )
    $config = Get-FirstReleaseConfiguration
    if (-not (Test-HexDigest $CandidateManifestSha256) -or -not (Test-HexDigest $SourceSha 40) -or
        -not (Test-HexDigest $SmokeEvidenceSha256) -or -not (Test-HexDigest $YtDlpSha256) -or
        [string]::IsNullOrWhiteSpace($YtDlpTag)) { throw 'release_manifest_invalid' }
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $candidate = [IO.Path]::GetFullPath($CandidateRoot)
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw 'release_candidate_missing' }
    $candidateManifestPath = Join-Path $candidate 'candidate-manifest.json'
    if (-not (Test-Path -LiteralPath $candidateManifestPath -PathType Leaf)) { throw 'release_candidate_manifest_missing' }
    $actualCandidateManifestSha = (Get-FileHash -LiteralPath $candidateManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualCandidateManifestSha -cne $CandidateManifestSha256.ToLowerInvariant()) { throw 'release_candidate_manifest_mismatch' }
    foreach ($doc in @('LICENSE','NOTICE','PROVENANCE.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $doc) -PathType Leaf)) { throw "release_document_missing:$doc" }
    }
    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputRoot)) | Out-Null
    $packageRoot = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $config.PackageName
    if (Test-Path -LiteralPath $packageRoot) { throw 'release_package_exists' }
    [IO.Directory]::CreateDirectory($packageRoot) | Out-Null
    try {
        Copy-ReleaseTree -SourceRoot $candidate -DestinationRoot $packageRoot
        foreach ($doc in @('LICENSE','NOTICE','PROVENANCE.md')) { Copy-Item -LiteralPath (Join-Path $source $doc) -Destination (Join-Path $packageRoot $doc) }
        $inventory = @(Get-ReleaseInventory -PackageRoot $packageRoot)
        $manifest = [ordered]@{
            schemaVersion = 1
            tag = $config.Tag
            repository = $config.Repository
            sourceCommit = $SourceSha.ToLowerInvariant()
            platform = $config.Platform
            directUpstream = [ordered]@{
                repository = $config.UpstreamRepository
                tag = $config.UpstreamTag
                commit = $config.UpstreamCommit
                runtimeAsset = $config.UpstreamAssetName
                runtimeArchiveSha256 = $config.UpstreamArchiveSha256.ToLowerInvariant()
            }
            candidateManifestSha256 = $CandidateManifestSha256.ToLowerInvariant()
            ytDlp = [ordered]@{ repository = 'yt-dlp/yt-dlp-nightly-builds'; channel = 'nightly'; tag = $YtDlpTag; sha256 = $YtDlpSha256.ToLowerInvariant() }
            smoke = [ordered]@{ mode = 'artifact-only'; evidenceSha256 = $SmokeEvidenceSha256.ToLowerInvariant(); guiInteractionProven = $false }
            files = $inventory
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        $manifestPath = Join-Path $packageRoot 'release-manifest.json'
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
        Test-ReleasePackage -PackageRoot $packageRoot | Out-Null
        return [pscustomobject]@{ PackageRoot = $packageRoot; ManifestPath = $manifestPath }
    }
    catch {
        if (Test-Path -LiteralPath $packageRoot) { Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Test-ReleasePackage {
    param([Parameter(Mandatory = $true)] [string] $PackageRoot)
    $config = Get-FirstReleaseConfiguration
    $root = [IO.Path]::GetFullPath($PackageRoot)
    $manifestPath = Join-Path $root 'release-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'release_manifest_missing' }
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'release_manifest_invalid' }
    if ($manifest.schemaVersion -ne 1 -or [string]$manifest.tag -cne $config.Tag -or
        [string]$manifest.repository -cne $config.Repository -or [string]$manifest.platform -cne $config.Platform -or
        -not (Test-HexDigest ([string]$manifest.sourceCommit) 40) -or
        [string]$manifest.directUpstream.repository -cne $config.UpstreamRepository -or
        [string]$manifest.directUpstream.tag -cne $config.UpstreamTag -or
        [string]$manifest.directUpstream.commit -cne $config.UpstreamCommit -or
        ([string]$manifest.directUpstream.runtimeArchiveSha256).ToLowerInvariant() -cne $config.UpstreamArchiveSha256.ToLowerInvariant() -or
        -not (Test-HexDigest ([string]$manifest.candidateManifestSha256) 64) -or
        [string]$manifest.smoke.mode -cne 'artifact-only' -or [bool]$manifest.smoke.guiInteractionProven -ne $false -or
        -not (Test-HexDigest ([string]$manifest.smoke.evidenceSha256) 64) -or
        [string]$manifest.ytDlp.repository -cne 'yt-dlp/yt-dlp-nightly-builds' -or
        [string]$manifest.ytDlp.channel -cne 'nightly' -or -not (Test-HexDigest ([string]$manifest.ytDlp.sha256) 64)) {
        throw 'release_manifest_invalid'
    }
    $entries = @($manifest.files)
    $seen = @{}
    $listed = @()
    foreach ($entry in $entries) {
        $relative = [string]$entry.path
        if (-not (Test-SafeReleaseRelativePath -Path $relative) -or $relative -ceq 'release-manifest.json' -or
            -not (Test-HexDigest ([string]$entry.sha256) 64) -or [long]$entry.length -lt 0) { throw 'release_manifest_invalid' }
        $key = $relative.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw 'release_manifest_invalid' }
        $seen[$key] = $true
        $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
        $prefix = $root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
        if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'release_package_inventory_mismatch' }
        $file = Get-Item -LiteralPath $full
        if ($file.Length -ne [long]$entry.length -or (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() -cne ([string]$entry.sha256).ToLowerInvariant()) {
            throw 'release_package_inventory_mismatch'
        }
        $listed += $relative
    }
    $actual = @(Get-ReleaseInventory -PackageRoot $root | ForEach-Object { [string]$_.path } | Sort-Object)
    $listedSorted = @($listed | Sort-Object)
    if ($actual.Count -ne $listedSorted.Count) { throw 'release_package_inventory_mismatch' }
    for ($i = 0; $i -lt $actual.Count; $i++) { if ($actual[$i] -cne $listedSorted[$i]) { throw 'release_package_inventory_mismatch' } }
    $candidateManifest = Join-Path $root 'candidate-manifest.json'
    if (-not (Test-Path -LiteralPath $candidateManifest -PathType Leaf) -or
        (Get-FileHash -LiteralPath $candidateManifest -Algorithm SHA256).Hash.ToLowerInvariant() -cne ([string]$manifest.candidateManifestSha256).ToLowerInvariant()) {
        throw 'release_package_inventory_mismatch'
    }
    return $manifest
}

function Write-ReleaseChecksum {
    param([Parameter(Mandatory = $true)] [string] $ZipPath, [Parameter(Mandatory = $true)] [string] $OutputDirectory)
    $config = Get-FirstReleaseConfiguration
    $zip = [IO.Path]::GetFullPath($ZipPath)
    if (-not (Test-Path -LiteralPath $zip -PathType Leaf) -or (Split-Path -Leaf $zip) -cne $config.ZipName) { throw 'release_zip_invalid' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory)) | Out-Null
    $checksumPath = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) $config.ChecksumName
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($checksumPath, ($hash + '  ' + $config.ZipName + "`n"), [Text.UTF8Encoding]::new($false))
    return $checksumPath
}

function Test-ReleaseChecksum {
    param([Parameter(Mandatory = $true)] [string] $ZipPath, [Parameter(Mandatory = $true)] [string] $ChecksumPath)
    $config = Get-FirstReleaseConfiguration
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf) -or -not (Test-Path -LiteralPath $ChecksumPath -PathType Leaf)) { throw 'release_checksum_missing' }
    if ((Split-Path -Leaf $ZipPath) -cne $config.ZipName -or (Split-Path -Leaf $ChecksumPath) -cne $config.ChecksumName) { throw 'release_checksum_invalid' }
    $text = [IO.File]::ReadAllText([IO.Path]::GetFullPath($ChecksumPath), [Text.UTF8Encoding]::new($false)).TrimEnd("`r","`n")
    $pattern = '^([0-9a-f]{64})  ' + [regex]::Escape($config.ZipName) + '$'
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) { throw 'release_checksum_invalid' }
    $actual = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $match.Groups[1].Value) { throw 'release_checksum_mismatch' }
    return $actual
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Output 'Release factory library loaded. No release action is performed without an explicit caller.'
}
