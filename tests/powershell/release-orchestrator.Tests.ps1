$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Factory = Join-Path $RepositoryRoot 'tools\release-factory.ps1'
$Orchestrator = Join-Path $RepositoryRoot 'tools\release-orchestrator.ps1'
$script:Failures = 0
$script:Tests = 0

function Assert-True { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Equal { param($Expected,$Actual,[string]$Message='values differ') if ($Expected -cne $Actual) { throw "$Message expected='$Expected' actual='$Actual'" } }
function Assert-Throws {
    param([scriptblock]$Action,[string]$ExpectedPattern)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    if ($null -eq $caught) { throw 'expected action to throw' }
    if ($caught.ToString() -notmatch $ExpectedPattern) { throw "unexpected exception: $caught" }
}
function Invoke-Test {
    param([string]$Name,[scriptblock]$Body)
    $script:Tests++
    try { & $Body; Write-Host "PASS: $Name" }
    catch { $script:Failures++; Write-Host "FAIL: $Name"; Write-Host $_ }
}
function New-TempDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('karon-release-orchestrator-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

if (-not (Test-Path -LiteralPath $Factory -PathType Leaf)) { throw "release factory missing: $Factory" }
. $Factory
if (-not (Test-Path -LiteralPath $Orchestrator -PathType Leaf)) { throw "release orchestrator implementation is missing: $Orchestrator" }
. $Orchestrator

Invoke-Test 'release orchestrator exposes only the intended build stages' {
    foreach ($name in @('New-VerifiedUpstreamParentRuntime','Initialize-CiNightlyParentRuntime','Invoke-ReleaseCandidateBuild','Invoke-ReleaseArtifactSmoke')) {
        Assert-True ($null -ne (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) "missing function $name"
    }
}

Invoke-Test 'upstream download URL is fixed to the reviewed x64 asset' {
    $url = Get-UpstreamReleaseAssetUrl
    Assert-Equal 'https://github.com/ErrorFlynn/ytdlp-interface/releases/download/v2.19.1/ytdlp-interface.7z' $url
}

Invoke-Test 'CI nightly initialization refuses a missing disposable parent runtime before network work' {
    $root = New-TempDirectory
    try { Assert-Throws { Initialize-CiNightlyParentRuntime -SourceRoot $RepositoryRoot -ParentRuntime (Join-Path $root 'missing') } 'release_parent_runtime_missing' }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'release path overlap helper distinguishes siblings from containment' {
    $root = New-TempDirectory
    try {
        $parent = Join-Path $root 'parent'; New-Item -ItemType Directory -Force -Path $parent | Out-Null
        $sibling = Join-Path $root 'candidate-base'; New-Item -ItemType Directory -Force -Path $sibling | Out-Null
        $child = Join-Path $parent 'child'; New-Item -ItemType Directory -Force -Path $child | Out-Null
        Assert-True (-not (Test-ReleasePathsOverlap -First $parent -Second $sibling)) 'sibling directories must not overlap'
        Assert-True (Test-ReleasePathsOverlap -First $parent -Second $child) 'parent/child directories must overlap'
        Assert-True (Test-ReleasePathsOverlap -First $parent -Second $parent) 'same directory must overlap'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'candidate build refuses missing source or parent inputs' {
    $root = New-TempDirectory
    try {
        Assert-Throws { Invoke-ReleaseCandidateBuild -SourceRoot (Join-Path $root 'missing-source') -ParentRuntime $root -CandidateBase (Join-Path $root 'candidates') } 'release_source_missing'
        Assert-Throws { Invoke-ReleaseCandidateBuild -SourceRoot $RepositoryRoot -ParentRuntime (Join-Path $root 'missing-parent') -CandidateBase (Join-Path $root 'candidates') } 'release_parent_runtime_missing'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'artifact smoke refuses malformed candidate manifest identity before launching GUI' {
    $root = New-TempDirectory
    try {
        $candidate = Join-Path $root 'candidate'; New-Item -ItemType Directory -Force -Path $candidate | Out-Null
        $parent = Join-Path $root 'parent'; New-Item -ItemType Directory -Force -Path $parent | Out-Null
        $downloads = Join-Path $root 'downloads'; New-Item -ItemType Directory -Force -Path $downloads | Out-Null
        Assert-Throws { Invoke-ReleaseArtifactSmoke -SourceRoot $RepositoryRoot -CandidateRoot $candidate -ParentRuntime $parent -CandidateManifestSha256 'not-a-hash' -DownloadsPath $downloads } 'release_candidate_manifest_invalid'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'release smoke automation suppresses yt-dlp stdout before returning marker' {
    $orchestratorText = Get-Content -LiteralPath $Orchestrator -Raw
    Assert-True ($orchestratorText -match '\$downloadOutput\s*=\s*@\(&\s*\$ytDlp') 'yt-dlp output must be captured instead of leaking into the automation marker pipeline'
    Assert-True ($orchestratorText -match 'return \[pscustomobject\]@\{\s*Completed = \$true; GuiProcessId = \$guiPid; Url = \$url; OutputDirectory = \$outputDirectory \}') 'automation must return exactly the marker object after capture'
}

Invoke-Test 'release CI does not weaken the public unelevated updater policy' {
    $runtimeModule = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'tools\runtime-maintenance.psm1') -Raw
    $orchestratorText = Get-Content -LiteralPath $Orchestrator -Raw
    Assert-True ($runtimeModule -match "if \(Test-IsElevated\).*UpdateYtDlp must be run from an unelevated PowerShell process") 'public updater elevation gate disappeared'
    Assert-True ($orchestratorText -match 'Invoke-YtDlpTransaction') 'release CI is not using the verified transaction boundary'
    Assert-True ($orchestratorText -notmatch '(?m)^\s*UpdateYtDlp\s+-') 'release CI should not call the public interactive updater'
}

if ($script:Failures -gt 0) { throw "$($script:Failures) of $($script:Tests) release orchestrator tests failed." }
Write-Host "All $($script:Tests) release orchestrator tests passed."
exit 0
