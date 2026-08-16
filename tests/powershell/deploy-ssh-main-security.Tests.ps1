$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$DeployScript = Join-Path $RepositoryRoot 'tools\deploy-ssh-main.ps1'
$script:Failures = 0
$script:Tests = 0

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
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

function Assert-DeployRejected {
    param([hashtable] $Parameters, [string] $ExpectedPattern)
    $oldLocation = Get-Location
    try {
        $caught = $null
        try {
            & $DeployScript @Parameters | Out-Null
        }
        catch {
            $caught = $_
        }
        Assert-True ($null -ne $caught) 'deployment unexpectedly succeeded'
        if (-not [string]::IsNullOrWhiteSpace($ExpectedPattern)) {
            Assert-True ($caught.ToString() -match $ExpectedPattern) "unexpected rejection: $caught"
        }
    }
    finally {
        Set-Location -LiteralPath $oldLocation
    }
}

function Invoke-DeployAccepted {
    param([hashtable] $Parameters)
    $oldLocation = Get-Location
    try {
        & $DeployScript @Parameters | Out-Null
    }
    finally {
        Set-Location -LiteralPath $oldLocation
    }
}

function New-FakeRepo {
    $base = Join-Path ([IO.Path]::GetTempPath()) ("karon-deploy-security-" + [guid]::NewGuid().ToString('N'))
    $repo = Join-Path $base 'ytdlp-korean-interface\src'
    New-Item -ItemType Directory -Force -Path (Join-Path $repo '.git') | Out-Null
    return $repo
}

function Reset-FakeState {
    $global:KaronDeployTestState = @{
        RepoRoot = (New-FakeRepo)
        CanonicalUrl = 'git@github.com:KaronLabs/ytdlp-korean-interface.git'
        FetchUrl = 'git@github.com:KaronLabs/ytdlp-korean-interface.git'
        PushUrl = 'git@github.com:KaronLabs/ytdlp-korean-interface.git'
        CurrentBranch = 'main'
        LocalSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        RemoteSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        StatusShort = ''
        CachedPaths = @()
        SshMessage = "Hi KaronLabs! You've successfully authenticated, but GitHub does not provide shell access."
        SshExitCode = 1
        PushExitCode = 0
        GitCalls = [System.Collections.Generic.List[string]]::new()
    }
}

function global:ssh {
    $global:LASTEXITCODE = [int] $global:KaronDeployTestState.SshExitCode
    Write-Output ([string] $global:KaronDeployTestState.SshMessage)
}

function global:git {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]] $GitArgs)

    $state = $global:KaronDeployTestState
    $argv = @($GitArgs | ForEach-Object { [string] $_ })
    $joined = $argv -join ' '
    $state.GitCalls.Add($joined)
    $global:LASTEXITCODE = 0

    if ($joined -eq 'rev-parse --show-toplevel') { return $state.RepoRoot }
    if ($joined -eq 'rev-parse --abbrev-ref HEAD') { return $state.CurrentBranch }
    if ($joined -eq 'symbolic-ref --quiet --short HEAD') { return $state.CurrentBranch }
    if ($joined -eq 'remote get-url origin') { return $state.FetchUrl }
    if ($joined -eq 'remote get-url --all origin') { return $state.FetchUrl }
    if ($joined -eq 'remote get-url --push --all origin') { return $state.PushUrl }
    if ($joined -eq 'status --short') { return $state.StatusShort }
    if ($joined -match '^diff --cached --name-only(?: -z)?(?: --)?$') {
        if ($joined -match ' -z') {
            if ($state.CachedPaths.Count -eq 0) { return '' }
            return (($state.CachedPaths -join "`0") + "`0")
        }
        return $state.CachedPaths
    }
    if ($joined -match '^add(?: --)? ') {
        $start = 1
        if ($argv.Count -gt 1 -and $argv[1] -eq '--') { $start = 2 }
        $paths = @($argv[$start..($argv.Count - 1)] | ForEach-Object { $_ -replace '^:\(literal\)', '' })
        $state.CachedPaths = $paths
        return
    }
    if ($argv.Count -ge 3 -and $argv[0] -eq 'commit' -and $argv[1] -eq '-m') {
        $state.CachedPaths = @()
        return
    }
    if ($joined -eq 'rev-parse HEAD' -or $joined -eq 'rev-parse --verify HEAD^{commit}') { return $state.LocalSha }
    if ($argv.Count -ge 2 -and $argv[0] -eq 'ls-remote') {
        $ref = $argv[-1]
        if ([string]::IsNullOrWhiteSpace([string] $state.RemoteSha)) { return }
        return "$($state.RemoteSha)`t$ref"
    }
    if ($argv.Count -ge 3 -and $argv[0] -eq 'push') {
        $global:LASTEXITCODE = [int] $state.PushExitCode
        if ($state.PushExitCode -eq 0) { $state.RemoteSha = $state.LocalSha }
        return
    }

    throw "unexpected fake git invocation: $joined"
}

Invoke-Test 'policy-critical destination cannot be overridden by caller' {
    Reset-FakeState
    $state = $global:KaronDeployTestState
    $parameters = @{
        RepoRoot = $state.RepoRoot
        ExpectedRemote = 'git@github.com:attacker/evil.git'
        Branch = 'evil'
        RemoteName = 'origin'
        WhatIf = $true
    }
    $state.FetchUrl = 'git@github.com:attacker/evil.git'
    $state.RemoteSha = $state.LocalSha
    Assert-DeployRejected -Parameters $parameters -ExpectedPattern 'parameter|cannot|expected|canonical|remote|branch'
}

Invoke-Test 'non-main current branch is rejected before push' {
    Reset-FakeState
    $state = $global:KaronDeployTestState
    $state.CurrentBranch = 'feature/accidental'
    Assert-DeployRejected -Parameters @{ RepoRoot = $state.RepoRoot } -ExpectedPattern 'main|branch'
    Assert-True (-not ($state.GitCalls | Where-Object { $_ -match '^push ' })) 'push ran from a non-main branch'
}

Invoke-Test 'mismatched remote push URL is rejected before source can be sent elsewhere' {
    Reset-FakeState
    $state = $global:KaronDeployTestState
    $state.PushUrl = 'git@github.com:attacker/collector.git'
    Assert-DeployRejected -Parameters @{ RepoRoot = $state.RepoRoot } -ExpectedPattern 'push|remote|url|canonical'
    Assert-True (-not ($state.GitCalls | Where-Object { $_ -match '^push ' })) 'push ran despite mismatched push URL'
}

Invoke-Test 'pre-staged unrelated files are rejected in StagePaths mode' {
    Reset-FakeState
    $state = $global:KaronDeployTestState
    $state.CachedPaths = @('secrets/local-token.txt')
    Assert-DeployRejected -Parameters @{
        RepoRoot = $state.RepoRoot
        StagePaths = @('README.md')
        CommitMessage = 'docs: test'
    } -ExpectedPattern 'staged|index|clean'
    Assert-True (-not ($state.GitCalls | Where-Object { $_ -match '^commit ' })) 'commit ran with pre-staged unrelated content'
}

Invoke-Test 'git pathspec magic cannot broaden StagePaths' {
    Reset-FakeState
    $state = $global:KaronDeployTestState
    Assert-DeployRejected -Parameters @{
        RepoRoot = $state.RepoRoot
        StagePaths = @(':(glob)**')
        CommitMessage = 'docs: test'
    } -ExpectedPattern 'path|literal|stage|invalid'
    Assert-True (-not ($state.GitCalls | Where-Object { $_ -match '^add ' })) 'git add received a magic pathspec'
}

Invoke-Test 'push failure cannot be reported as PUSH_OK' {
    Reset-FakeState
    $state = $global:KaronDeployTestState
    $state.PushExitCode = 1
    $state.RemoteSha = $state.LocalSha
    Assert-DeployRejected -Parameters @{ RepoRoot = $state.RepoRoot } -ExpectedPattern 'push|git|failed|exit'
}

Invoke-Test 'successful push is pinned to canonical URL and verified commit SHA, never HEAD' {
    Reset-FakeState
    $state = $global:KaronDeployTestState
    Invoke-DeployAccepted -Parameters @{ RepoRoot = $state.RepoRoot }
    $push = @($state.GitCalls | Where-Object { $_ -match '^push ' })
    Assert-True ($push.Count -eq 1) "expected one push, got $($push.Count)"
    Assert-True ($push[0] -match [regex]::Escape($state.CanonicalUrl)) "push did not use canonical URL: $($push[0])"
    Assert-True ($push[0] -match [regex]::Escape($state.LocalSha)) "push did not pin local SHA: $($push[0])"
    Assert-True ($push[0] -notmatch 'HEAD:') "push still uses mutable HEAD ref: $($push[0])"
}

Invoke-Test 'SSH authentication must be the expected GitHub login' {
    Reset-FakeState
    $state = $global:KaronDeployTestState
    $state.SshMessage = "Hi random-user! You've successfully authenticated, but GitHub does not provide shell access."
    Assert-DeployRejected -Parameters @{ RepoRoot = $state.RepoRoot } -ExpectedPattern 'KaronLabs|identity|login|SSH'
    Assert-True (-not ($state.GitCalls | Where-Object { $_ -match '^push ' })) 'push ran under unexpected GitHub SSH identity'
}

Remove-Item function:\global:git -ErrorAction SilentlyContinue
Remove-Item function:\global:ssh -ErrorAction SilentlyContinue
Remove-Variable -Name KaronDeployTestState -Scope Global -ErrorAction SilentlyContinue

if ($script:Failures -gt 0) {
    throw "$($script:Failures) of $($script:Tests) deploy security tests failed."
}

Write-Host "All $($script:Tests) deploy security tests passed."
exit 0
