$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Factory = Join-Path $RepositoryRoot 'tools\release-factory.ps1'
$ArchiveHelper = Join-Path $RepositoryRoot 'tools\release-archive.ps1'
$Workflow = Join-Path $RepositoryRoot '.github\workflows\release-v2.19.1-karon.1.yml'
$Notes = Join-Path $RepositoryRoot 'release\notes\v2.19.1-karon.1.md'
$Request = Join-Path $RepositoryRoot 'release\requests\v2.19.1-karon.1.json'
$script:Failures = 0; $script:Tests = 0

function Assert-True { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Equal { param($Expected,$Actual,[string]$Message='values differ') if ($Expected -cne $Actual) { throw "$Message expected='$Expected' actual='$Actual'" } }
function Assert-Throws {
    param([scriptblock]$Action,[string]$ExpectedPattern)
    $caught=$null; try { & $Action | Out-Null } catch { $caught=$_ }
    if ($null -eq $caught) { throw 'expected action to throw' }
    if ($caught.ToString() -notmatch $ExpectedPattern) { throw "unexpected exception: $caught" }
}
function Invoke-Test { param([string]$Name,[scriptblock]$Body) $script:Tests++; try { & $Body; Write-Host "PASS: $Name" } catch { $script:Failures++; Write-Host "FAIL: $Name"; Write-Host $_ } }
function New-TempDirectory { $p=Join-Path ([IO.Path]::GetTempPath()) ('karon-publish-test-'+[Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $p|Out-Null; $p }

. $Factory
if (-not (Test-Path -LiteralPath $ArchiveHelper -PathType Leaf)) { throw "release archive helper is missing: $ArchiveHelper" }
. $ArchiveHelper

Invoke-Test 'release ZIP preserves exactly one canonical top-level directory' {
    $root=New-TempDirectory
    try {
        $config=Get-FirstReleaseConfiguration
        $package=Join-Path $root $config.PackageName; New-Item -ItemType Directory -Force -Path (Join-Path $package 'locales')|Out-Null
        [IO.File]::WriteAllText((Join-Path $package 'release-manifest.json'),'{}')
        [IO.File]::WriteAllText((Join-Path $package 'ytdlp-interface.exe'),'fixture')
        [IO.File]::WriteAllText((Join-Path $package 'locales\ko-KR.json'),'{}')
        $zip=New-ReleaseZip -PackageRoot $package -OutputDirectory $root
        Test-ReleaseZip -ZipPath $zip -PackageRoot $package | Out-Null
    } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'release ZIP validation rejects traversal entries' {
    $root=New-TempDirectory
    try {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $config=Get-FirstReleaseConfiguration
        $package=Join-Path $root $config.PackageName; New-Item -ItemType Directory -Force -Path $package|Out-Null
        [IO.File]::WriteAllText((Join-Path $package 'release-manifest.json'),'{}')
        $zip=Join-Path $root $config.ZipName
        $stream=[IO.File]::Open($zip,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
            try { $null=$archive.CreateEntry('../escape.txt') } finally { $archive.Dispose() }
        } finally { $stream.Dispose() }
        Assert-Throws { Test-ReleaseZip -ZipPath $zip -PackageRoot $package } 'release_zip_invalid'
    } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'publication workflow is fixed, minimal-permission, and verification-first' {
    Assert-True (Test-Path -LiteralPath $Workflow -PathType Leaf) 'publication workflow missing'
    $text=Get-Content -LiteralPath $Workflow -Raw
    Assert-True ($text -match 'runs-on:\s*windows-2022') 'workflow must use windows-2022'
    Assert-True ($text -match '(?ms)^permissions:\s*\r?\n\s+contents:\s*write\s*$') 'workflow must declare contents write explicitly'
    Assert-True ($text -notmatch 'write-all|id-token:\s*write|actions:\s*write|packages:\s*write') 'workflow grants unrelated write permissions'
    Assert-True ($text -match "release/requests/v2\.19\.1-karon\.1\.json") 'workflow trigger is not request-scoped'
    Assert-True ($text -match 'ref:\s*\$\{\{\s*github\.sha\s*\}\}') 'checkout is not pinned to github.sha'
    Assert-True ($text -match 'GH_TOKEN:\s*\$\{\{\s*github\.token\s*\}\}') 'GH_TOKEN is not repository-scoped github.token'
    Assert-True ($text -notmatch 'PERSONAL_ACCESS_TOKEN|PAT|BEGIN OPENSSH PRIVATE KEY|--clobber|--force') 'workflow contains forbidden credential/overwrite path'
    $verifyIndex=$text.IndexOf('Build, smoke, and verify release payload')
    $publishIndex=$text.IndexOf('Publish verified release')
    Assert-True ($verifyIndex -ge 0 -and $publishIndex -gt $verifyIndex) 'publication appears before release verification'
    Assert-True ($text -match 'gh release create') 'draft release creation missing'
    Assert-True ($text -match '--target\s+\$sourceSha') 'release target is not exact source SHA'
    Assert-True ($text -match '--draft') 'release must begin as draft'
    Assert-True ($text -match 'gh release edit.+--draft=false') 'draft publication step missing'
    Assert-True ($text -match 'gh release download') 'fresh public asset download verification missing'
}

Invoke-Test 'release notes preserve upstream lineage and verification instructions' {
    Assert-True (Test-Path -LiteralPath $Notes -PathType Leaf) 'release notes missing'
    $text=Get-Content -LiteralPath $Notes -Raw -Encoding UTF8
    $karonCodes = @(0xC791,0xC740,0x20,0xC77C,0xC774,0xC5C8,0xB294,0xB370,0x20,0xC791,0xC9C0,0x20,0xC54A,0xAC8C,0x20,0xB410,0xC2B5,0xB2C8,0xB2E4)
    $karonLine = -join ($karonCodes | ForEach-Object { [char]$_ })
    Assert-True ($text -match 'ErrorFlynn/ytdlp-interface.*v2\.19\.1') 'direct upstream disclosure missing'
    Assert-True ($text -match 'SHA256SUMS\.txt') 'checksum instructions missing'
    Assert-True ($text -match 'release-manifest\.json') 'release manifest instructions missing'
    Assert-True ($text -match 'candidate-manifest\.json') 'candidate manifest instructions missing'
    Assert-True ($text.Contains($karonLine)) 'KaronLabs release line missing'
    Assert-True ($text -notmatch 'machine-proven GUI|GUI interaction proven') 'notes overclaim headless GUI proof'
}

Invoke-Test 'one-time request is not committed during factory implementation' {
    Assert-True (-not (Test-Path -LiteralPath $Request)) 'release request must not exist before pre-trigger verification'
}

if ($script:Failures -gt 0) { throw "$($script:Failures) of $($script:Tests) publication contract tests failed." }
Write-Host "All $($script:Tests) publication contract tests passed."
exit 0
