$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$CandidateBuilder = Join-Path $RepositoryRoot 'tools\build-candidate.ps1'
$script:GitPath = (Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
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

function Write-TestUtf8 {
    param([string] $Path, [string] $Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Invoke-TestGit {
    param([string] $Repository, [string[]] $Arguments)
    $output = @(& $script:GitPath -c core.autocrlf=false -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('test_git_failed: git ' + ($Arguments -join ' ') + ': ' + (($output | Out-String).Trim())) }
    return (($output | Out-String).Trim())
}

function New-TestCase {
    param([switch] $GitRepository)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('karon-candidate-provenance-' + [Guid]::NewGuid().ToString('N'))
    $source = Join-Path $root 'source'
    $parent = Join-Path $root 'parent'
    [IO.Directory]::CreateDirectory((Join-Path $source 'ytdlp-interface')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $source 'locales')) | Out-Null
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    Write-TestUtf8 (Join-Path $source 'ytdlp-interface\ytdlp-interface.sln') "fixture`n"
    Write-TestUtf8 (Join-Path $source 'ytdlp-interface\ytdlp-interface.vcxproj') "<PlatformToolset>v143</PlatformToolset>`n"
    Write-TestUtf8 (Join-Path $source 'locales\ko-KR.json') "{}`n"
    Write-TestUtf8 (Join-Path $parent 'ytdlp-interface.json') "{}`n"
    if ($GitRepository) {
        [void](Invoke-TestGit $source @('init', '-q'))
        [void](Invoke-TestGit $source @('config', 'user.email', 'candidate-provenance@example.invalid'))
        [void](Invoke-TestGit $source @('config', 'user.name', 'Candidate Provenance Test'))
        [void](Invoke-TestGit $source @('add', '--', 'ytdlp-interface/ytdlp-interface.sln', 'ytdlp-interface/ytdlp-interface.vcxproj', 'locales/ko-KR.json'))
        [void](Invoke-TestGit $source @('commit', '-q', '-m', 'candidate source'))
    }
    return [pscustomobject]@{
        Root = $root
        Source = $source
        Parent = $parent
        CandidateBase = Join-Path $root 'candidate-output'
        DependencyArchives = Join-Path $root 'dependency-archives'
        RuntimeArchives = Join-Path $root 'runtime-archives'
    }
}

function Remove-TestCase {
    param([object] $Case)
    Remove-Item -LiteralPath $Case.Root -Recurse -Force -ErrorAction SilentlyContinue
}

. $CandidateBuilder

Invoke-Test 'clean detached source seals exact commit and tree through JSON' {
    $case = New-TestCase -GitRepository
    try {
        [void](Invoke-TestGit $case.Source @('checkout', '--detach', '-q'))
        $expectedCommit = Invoke-TestGit $case.Source @('rev-parse', '--verify', 'HEAD^{commit}')
        $expectedTree = Invoke-TestGit $case.Source @('rev-parse', '--verify', 'HEAD^{tree}')
        $attestation = Get-SourceAttestation -SourceRoot $case.Source -GitPath $script:GitPath
        Assert-True $attestation.Contains('tree') 'source attestation did not contain the Git tree'
        Assert-Equal $expectedCommit $attestation.commit 'source commit differs from Git HEAD'
        Assert-Equal $expectedTree $attestation.tree 'source tree differs from Git HEAD tree'

        $candidate = Join-Path $case.Root 'manifest-fixture'
        [IO.Directory]::CreateDirectory($candidate) | Out-Null
        Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $candidate 'ytdlp-interface.exe')
        foreach ($name in @('yt-dlp.exe', 'ffmpeg.exe', 'ffprobe.exe', 'deno.exe')) {
            Write-TestUtf8 (Join-Path $candidate $name) "fixture-$name`n"
        }
        Set-Item -Path Function:Invoke-CheckedExecutable -Value { param($Path, $Arguments, $Name) 'fixture-version' }
        $manifest = Get-CandidateManifest -CandidateRoot $candidate -Attestation ([ordered]@{ source = $attestation })
        $serialized = $manifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        Assert-Equal $expectedCommit $serialized.applicationSourceCommit 'serialized application source commit differs from Git HEAD'
        Assert-Equal $expectedTree $serialized.applicationSourceTree 'serialized application source tree differs from Git HEAD tree'
    }
    finally { Remove-TestCase $case }
}

Invoke-Test 'dirty source fails before candidate output exists' {
    $case = New-TestCase -GitRepository
    try {
        Write-TestUtf8 (Join-Path $case.Source 'untracked-dirty.txt') "dirty`n"
        Assert-Throws {
            Invoke-BuildCandidate -SourceRoot $case.Source -ParentRuntime $case.Parent -CandidateBase $case.CandidateBase -DependencyArchiveDirectory $case.DependencyArchives -RuntimeArchiveDirectory $case.RuntimeArchives
        } 'source_worktree_dirty'
        Assert-True (-not (Test-Path -LiteralPath $case.CandidateBase)) 'dirty source produced candidate output'
    }
    finally { Remove-TestCase $case }
}

Invoke-Test 'missing source fails before candidate output exists' {
    $case = New-TestCase
    try {
        $missing = Join-Path $case.Root 'missing-source'
        Assert-Throws {
            Invoke-BuildCandidate -SourceRoot $missing -ParentRuntime $case.Parent -CandidateBase $case.CandidateBase -DependencyArchiveDirectory $case.DependencyArchives -RuntimeArchiveDirectory $case.RuntimeArchives
        } 'Required build input is missing'
        Assert-True (-not (Test-Path -LiteralPath $case.CandidateBase)) 'missing source produced candidate output'
    }
    finally { Remove-TestCase $case }
}

Invoke-Test 'non-Git source fails before candidate output exists' {
    $case = New-TestCase
    try {
        Assert-Throws {
            Invoke-BuildCandidate -SourceRoot $case.Source -ParentRuntime $case.Parent -CandidateBase $case.CandidateBase -DependencyArchiveDirectory $case.DependencyArchives -RuntimeArchiveDirectory $case.RuntimeArchives
        } 'Git could not enumerate tracked candidate source inputs'
        Assert-True (-not (Test-Path -LiteralPath $case.CandidateBase)) 'non-Git source produced candidate output'
    }
    finally { Remove-TestCase $case }
}

Invoke-Test 'caller cannot supply application provenance fields' {
    $parameters = (Get-Command Invoke-BuildCandidate).Parameters.Keys
    Assert-True ($parameters -notcontains 'ApplicationSourceCommit') 'builder accepts a spoofed application source commit'
    Assert-True ($parameters -notcontains 'ApplicationSourceTree') 'builder accepts a spoofed application source tree'
}

if ($script:Failures -gt 0) { throw "$($script:Failures) of $($script:Tests) candidate provenance tests failed." }
Write-Host "All $($script:Tests) candidate provenance tests passed."
exit 0
