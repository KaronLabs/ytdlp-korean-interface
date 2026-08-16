$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ReleaseFactory = Join-Path $RepositoryRoot 'tools\release-factory.ps1'
$script:Failures = 0
$script:Tests = 0

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message = 'values differ')
    if ($Expected -cne $Actual) { throw "$Message expected='$Expected' actual='$Actual'" }
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $ExpectedPattern)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    if ($null -eq $caught) { throw 'expected action to throw' }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedPattern) -and $caught.ToString() -notmatch $ExpectedPattern) {
        throw "unexpected exception: $caught"
    }
}

function Invoke-Test {
    param([string] $Name, [scriptblock] $Body)
    $script:Tests++
    try {
        & $Body
        Write-Host "PASS: $Name"
    }
    catch {
        $script:Failures++
        Write-Host "FAIL: $Name"
        Write-Host $_
    }
}

function New-TempDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('karon-release-test-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function New-TestCandidate {
    param([string] $Root)
    $candidate = Join-Path $Root 'candidate'
    New-Item -ItemType Directory -Force -Path (Join-Path $candidate 'locales') | Out-Null
    foreach ($name in @('ytdlp-interface.exe', 'yt-dlp.exe', 'ffmpeg.exe', 'ffprobe.exe', 'deno.exe', '7z.dll', 'ytdlp-interface.json')) {
        [IO.File]::WriteAllText((Join-Path $candidate $name), "fixture-$name", [Text.UTF8Encoding]::new($false))
    }
    [IO.File]::WriteAllText((Join-Path $candidate 'locales\ko-KR.json'), '{"locale":"ko-KR"}', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $candidate 'candidate-manifest.json'), '{"schemaVersion":1}', [Text.UTF8Encoding]::new($false))
    return $candidate
}

function New-TestUpstreamRuntime {
    param([string] $Root, [string] $Name)
    $runtime = Join-Path $Root $Name
    New-Item -ItemType Directory -Force -Path $runtime | Out-Null
    foreach ($file in @('ytdlp-interface.exe','yt-dlp.exe','ffmpeg.exe','ffprobe.exe','deno.exe','7z.dll','ytdlp-interface.json')) {
        [IO.File]::WriteAllText((Join-Path $runtime $file), "fixture-$file", [Text.UTF8Encoding]::new($false))
    }
    return $runtime
}

if (-not (Test-Path -LiteralPath $ReleaseFactory -PathType Leaf)) {
    throw "release factory implementation is missing: $ReleaseFactory"
}
. $ReleaseFactory

Invoke-Test 'first release configuration is fixed' {
    $config = Get-FirstReleaseConfiguration
    Assert-Equal 'v2.19.1-karon.1' $config.Tag
    Assert-Equal 'ytdlp-korean-interface v2.19.1-karon.1' $config.Title
    Assert-Equal 'KaronLabs/ytdlp-korean-interface' $config.Repository
    Assert-Equal 'ErrorFlynn/ytdlp-interface' $config.UpstreamRepository
    Assert-Equal 'v2.19.1' $config.UpstreamTag
    Assert-Equal '2173316ebb5e50af49a2a4e939693fa8c3a3459c' $config.UpstreamCommit
    Assert-Equal '53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e' $config.UpstreamArchiveSha256.ToLowerInvariant()
    Assert-Equal 'ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip' $config.ZipName
    Assert-Equal 'SHA256SUMS.txt' $config.ChecksumName
}

Invoke-Test 'release request cannot change canonical metadata' {
    $request = [pscustomobject]@{
        schemaVersion = 1
        tag = 'v2.19.1-karon.2'
        platform = 'win-x64'
        upstreamRepository = 'ErrorFlynn/ytdlp-interface'
        upstreamTag = 'v2.19.1'
        upstreamCommit = '2173316ebb5e50af49a2a4e939693fa8c3a3459c'
        upstreamAsset = 'ytdlp-interface.7z'
        upstreamArchiveSha256 = '53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e'
    }
    Assert-Throws { Assert-ReleaseRequest -Request $request } 'release_request_invalid'
}

Invoke-Test 'release request rejects extra policy fields' {
    $request = [pscustomobject]@{
        schemaVersion = 1
        tag = 'v2.19.1-karon.1'
        platform = 'win-x64'
        upstreamRepository = 'ErrorFlynn/ytdlp-interface'
        upstreamTag = 'v2.19.1'
        upstreamCommit = '2173316ebb5e50af49a2a4e939693fa8c3a3459c'
        upstreamAsset = 'ytdlp-interface.7z'
        upstreamArchiveSha256 = '53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e'
        repository = 'attacker/evil'
    }
    Assert-Throws { Assert-ReleaseRequest -Request $request } 'release_request_invalid'
}

Invoke-Test 'release package detects unexpected files' {
    $root = New-TempDirectory
    try {
        $candidate = New-TestCandidate -Root $root
        foreach ($doc in @('LICENSE', 'NOTICE', 'PROVENANCE.md')) { [IO.File]::WriteAllText((Join-Path $root $doc), $doc) }
        $candidateManifestSha = (Get-FileHash -LiteralPath (Join-Path $candidate 'candidate-manifest.json') -Algorithm SHA256).Hash
        $package = New-ReleasePackage -SourceRoot $root -CandidateRoot $candidate -CandidateManifestSha256 $candidateManifestSha -SourceSha ('a' * 40) -SmokeEvidenceSha256 ('b' * 64) -YtDlpTag '2026.08.16.000000' -YtDlpSha256 ('c' * 64) -OutputRoot (Join-Path $root 'dist')
        [IO.File]::WriteAllText((Join-Path $package.PackageRoot 'unexpected.txt'), 'surprise')
        Assert-Throws { Test-ReleasePackage -PackageRoot $package.PackageRoot } 'release_package_inventory_mismatch'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'release manifest rejects traversal paths' {
    $root = New-TempDirectory
    try {
        $candidate = New-TestCandidate -Root $root
        foreach ($doc in @('LICENSE', 'NOTICE', 'PROVENANCE.md')) { [IO.File]::WriteAllText((Join-Path $root $doc), $doc) }
        $candidateManifestSha = (Get-FileHash -LiteralPath (Join-Path $candidate 'candidate-manifest.json') -Algorithm SHA256).Hash
        $package = New-ReleasePackage -SourceRoot $root -CandidateRoot $candidate -CandidateManifestSha256 $candidateManifestSha -SourceSha ('a' * 40) -SmokeEvidenceSha256 ('b' * 64) -YtDlpTag '2026.08.16.000000' -YtDlpSha256 ('c' * 64) -OutputRoot (Join-Path $root 'dist')
        $manifestPath = Join-Path $package.PackageRoot 'release-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.files[0].path = '../escape.txt'
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
        Assert-Throws { Test-ReleasePackage -PackageRoot $package.PackageRoot } 'release_manifest_invalid'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'release checksum binds exact ZIP bytes and name' {
    $root = New-TempDirectory
    try {
        $config = Get-FirstReleaseConfiguration
        $zip = Join-Path $root $config.ZipName
        [IO.File]::WriteAllBytes($zip, [byte[]](1,2,3,4,5))
        $sum = Write-ReleaseChecksum -ZipPath $zip -OutputDirectory $root
        Test-ReleaseChecksum -ZipPath $zip -ChecksumPath $sum | Out-Null
        [IO.File]::WriteAllText($sum, (('0' * 64) + '  ' + $config.ZipName + "`n"), [Text.UTF8Encoding]::new($false))
        Assert-Throws { Test-ReleaseChecksum -ZipPath $zip -ChecksumPath $sum } 'release_checksum_mismatch'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'upstream archive hash mismatch is terminal' {
    $root = New-TempDirectory
    try {
        $archive = Join-Path $root 'ytdlp-interface.7z'
        [IO.File]::WriteAllText($archive, 'tampered-upstream')
        Assert-Throws { Assert-UpstreamArchiveHash -ArchivePath $archive } 'upstream_archive_hash_mismatch'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'upstream runtime resolution rejects ambiguous payload roots' {
    $root = New-TempDirectory
    try {
        New-TestUpstreamRuntime -Root $root -Name 'runtime-a' | Out-Null
        New-TestUpstreamRuntime -Root $root -Name 'runtime-b' | Out-Null
        Assert-Throws { Resolve-UpstreamRuntimeRoot -ExtractedRoot $root } 'upstream_runtime_ambiguous'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'upstream runtime resolution rejects incomplete payload' {
    $root = New-TempDirectory
    try {
        $runtime = Join-Path $root 'runtime'
        New-Item -ItemType Directory -Force -Path $runtime | Out-Null
        [IO.File]::WriteAllText((Join-Path $runtime 'ytdlp-interface.exe'), 'only-product')
        Assert-Throws { Resolve-UpstreamRuntimeRoot -ExtractedRoot $root } 'upstream_runtime_incomplete'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:Failures -gt 0) { throw "$($script:Failures) of $($script:Tests) release factory tests failed." }
Write-Host "All $($script:Tests) release factory tests passed."
exit 0
