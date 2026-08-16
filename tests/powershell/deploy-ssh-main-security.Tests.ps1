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
    $script:RepoRoot = New-FakeRepo
    $script:CanonicalUrl = 'git@github.com:KaronLabs/ytdlp-korean-interface.git'
    $script:FetchUrl = $script:CanonicalUrl
    $script:PushUrl = $script:CanonicalUrl
    $script:CurrentBranch = 'main'
    $script:LocalSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $script:RemoteSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $script:StatusShort = ''
    $script:CachedPaths = @()
    $script:SshMessage = "Hi KaronLabs! You've successfully authenticated, but GitHub does not provide shell access."
    $script:SshExitCode = 1
    $script:PushExitCode = 0
    $script:GitCalls = [System.Collections.Generic.List[string]]::new()
}

function global:ssh {
    $script:LASTEXITCODE = $script:SshExitCode
    Write-Output $script:SshMessage
}

function global:git {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]] $GitArgs)

    $argv = @($GitArgs | ForEach-Object { [string] $_ })
    $joined = $argv -join ' '
    $script:GitCalls.Add($joined)
    $script:LASTEXITCODE = 0

    if ($joined -eq 'rev-parse --show-toplevel') { return $script:RepoRoot }
    if ($joined -eq 'rev-parse --abbrev-ref HEAD') { return $script:CurrentBranch }
    if ($joined -eq 'symbolic-ref --quiet --short HEAD') { return $script:CurrentBranch }
    if ($joined -eq 'remote get-url origin') { return $script:FetchUrl }
    if ($joined -eq 'remote get-url --all origin') { return $script:FetchUrl }
    if ($joined -eq 'remote get-url --push --all origin') { return $script:PushUrl }
    if ($joined -eq 'status --short') { return $script:StatusShort }
    if ($joined -match '^diff --cached --name-only(?: -z)?(?: --)?$') {
        if ($joined -match ' -z') { return (($script:CachedPaths -join "`0") + $(if ($script:CachedPaths.Count) { "`0" } else { '' })) }
        return $script:CachedPaths
    }
    if ($joined -match '^add -- ') {
        $paths = @($argv[2..($argv.Count - 1)] | ForEach-Object { $_ -replace '^:\(literal\)', '' })
        $script:CachedPaths = $paths
        return
    }
    if ($argv.Count -ge 3 -and $argv[0] -eq 'commit' -and $argv[1] -eq '-m') {
        $script:CachedPaths = @()
        return
    }
    if ($joined -eq 'rev-parse HEAD' -or $joined -eq 'rev-parse --verify HEAD^{commit}') { return $script:LocalSha }
    if ($argv.Count -ge 2 -and $argv[0] -eq 'ls-remote') {
        $ref = $argv[-1]
        if ([string]::IsNullOrWhiteSpace($script:RemoteSha)) { return }
        return "$($script:RemoteSha)`t$ref"
    }
    if ($argv.Count -ge 3 -and $argv[0] -eq 'push') {
        $script:LASTEXITCODE = $script:PushExitCode
        if ($script:PushExitCode -eq 0) { $script:RemoteSha = $script:LocalSha }
        return
    }

    throw "unexpected fake git invocation: $joined"
}

Invoke-Test 'policy-critical destination cannot be overridden by caller' {
    Reset-FakeState
    $parameters = @{
        RepoRoot = $script:RepoRoot
        ExpectedRemote = 'git@github.com:attacker/evil.git'
        Branch = 'evil'
        RemoteName = 'origin'
        WhatIf = $true
    }
    $script:FetchUrl = 'git@github.com:attacker/evil.git'
    $script:RemoteSha = $script:LocalSha
    Assert-DeployRejected -Parameters $parameters -ExpectedPattern 'parameter|cannot|expected|canonical|remote|branch'
}

Invoke-Test 'non-main current branch is rejected before push' {
    Reset-FakeState
    $script:CurrentBranch = 'feature/accidental'
    Assert-DeployRejected -Parameters @{ RepoRoot = $script:RepoRoot } -ExpectedPattern 'main|branch'
    Assert-True (-not ($script:GitCalls | Where-Object { $_ -match '^push ' })) 'push ran from a non-main branch'
}

Invoke-Test 'mismatched remote push URL is rejected before source can be sent elsewhere' {
    Reset-FakeState
    $script:PushUrl = 'git@github.com:attacker/collector.git'
    Assert-DeployRejected -Parameters @{ RepoRoot = $script:RepoRoot } -ExpectedPattern 'push|remote|url|canonical'
    Assert-True (-not ($script:GitCalls | Where-Object { $_ -match '^push ' })) 'push ran despite mismatched push URL'
}

Invoke-Test 'pre-staged unrelated files are rejected in StagePaths mode' {
    Reset-FakeState
    $script:CachedPaths = @('secrets/local-token.txt')
    Assert-DeployRejected -Parameters @{
        RepoRoot = $script:RepoRoot
        StagePaths = @('README.md')
        CommitMessage = 'docs: test'
    } -ExpectedPattern 'staged|index|clean'
    Assert-True (-not ($script:GitCalls | Where-Object { $_ -match '^commit ' })) 'commit ran with pre-staged unrelated content'
}

Invoke-Test 'git pathspec magic cannot broaden StagePaths' {
    Reset-FakeState
    Assert-DeployRejected -Parameters @{
        RepoRoot = $script:RepoRoot
        StagePaths = @(':(glob)**')
        CommitMessage = 'docs: test'
    } -ExpectedPattern 'path|literal|stage|invalid'
    Assert-True (-not ($script:GitCalls | Where-Object { $_ -match '^add ' })) 'git add received a magic pathspec'
}

Invoke-Test 'push failure cannot be reported as PUSH_OK' {
    Reset-FakeState
    $script:PushExitCode = 1
    $script:RemoteSha = $script:LocalSha
    Assert-DeployRejected -Parameters @{ RepoRoot = $script:RepoRoot } -ExpectedPattern 'push|git|failed|exit'
}

Invoke-Test 'successful push is pinned to canonical URL and verified commit SHA, never HEAD' {
    Reset-FakeState
    Invoke-DeployAccepted -Parameters @{ RepoRoot = $script:RepoRoot }
    $push = @($script:GitCalls | Where-Object { $_ -match '^push ' })
    Assert-True ($push.Count -eq 1) "expected one push, got $($push.Count)"
    Assert-True ($push[0] -match [regex]::Escape($script:CanonicalUrl)) "push did not use canonical URL: $($push[0])"
    Assert-True ($push[0] -match [regex]::Escape($script:LocalSha)) "push did not pin local SHA: $($push[0])"
    Assert-True ($push[0] -notmatch 'HEAD:') "push still uses mutable HEAD ref: $($push[0])"
}

Invoke-Test 'SSH authentication must be the expected GitHub login' {
    Reset-FakeState
    $script:SshMessage = "Hi random-user! You've successfully authenticated, but GitHub does not provide shell access."
    Assert-DeployRejected -Parameters @{ RepoRoot = $script:RepoRoot } -ExpectedPattern 'KaronLabs|identity|login|SSH'
    Assert-True (-not ($script:GitCalls | Where-Object { $_ -match '^push ' })) 'push ran under unexpected GitHub SSH identity'
}

Remove-Item function:\global:git -ErrorAction SilentlyContinue
Remove-Item function:\global:ssh -ErrorAction SilentlyContinue

if ($script:Failures -gt 0) {
    throw "$($script:Failures) of $($script:Tests) deploy security tests failed."
}

Write-Host "All $($script:Tests) deploy security tests passed."
