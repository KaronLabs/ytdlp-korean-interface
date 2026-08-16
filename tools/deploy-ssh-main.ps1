[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $RepoRoot = (Join-Path $PSScriptRoot '..'),
    [string] $RemoteName = 'origin',
    [string] $ExpectedRemote = 'git@github.com:KaronLabs/ytdlp-korean-interface.git',
    [string] $Branch = 'main',
    [string[]] $StagePaths = @(),
    [string] $CommitMessage,
    [switch] $AllowMainBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    $path = [IO.Path]::GetFullPath($RepoRoot)
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "RepoRoot not found: $path" }
    if (-not (Test-Path -LiteralPath (Join-Path $path '.git') -PathType Container)) {
        throw "RepoRoot is not a git repo: $path"
    }
    return $path
}

function Assert-Root {
    param([string] $RootPath)
    $normalizedRoot = ($RootPath -replace '/', '\')
    if ($normalizedRoot -notmatch '\\ytdlp-korean-interface\\src$') {
        throw "Deployment script must run from ytdlp-korean-interface src worktree. Found: $RootPath"
    }
}

function Get-RemoteUrl {
    param([string] $Remote)
    $url = (& git remote get-url $Remote | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($url)) { throw "remote '$Remote' is not configured." }
    return $url
}

function Invoke-StrictShaCheck {
    param([string] $Remote, [string] $BranchName)
    $raw = (git ls-remote $Remote ("refs/heads/$BranchName") | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $parts = ($raw -split '\s+')
    if ($parts.Count -lt 1 -or [string]::IsNullOrWhiteSpace($parts[0])) { return $null }
    return $parts[0]
}

function Invoke-SshAuthCheck {
    $msg = (& ssh -T git@github.com 2>&1 | Out-String)
    if (-not ($msg -match 'successfully authenticated')) {
        throw "SSH to github.com not verified: $msg"
    }
}

Set-Location -LiteralPath (Resolve-RepoRoot)
$root = (git rev-parse --show-toplevel).Trim()
Assert-Root -RootPath $root

Invoke-SshAuthCheck

$remote = Get-RemoteUrl -Remote $RemoteName
if ($remote -ne $ExpectedRemote) {
    throw "origin must be '$ExpectedRemote'. current='$remote'"
}

if (($StagePaths.Count -gt 0) -and [string]::IsNullOrWhiteSpace($CommitMessage)) {
    throw 'CommitMessage is required when StagePaths is provided.'
}
if (($StagePaths.Count -eq 0) -and (-not [string]::IsNullOrWhiteSpace($CommitMessage))) {
    throw 'StagePaths is required when CommitMessage is provided.'
}

if ($StagePaths.Count -gt 0) {
    git add -- $StagePaths
    git commit -m $CommitMessage
    git status --short
}
else {
    $status = (& git status --short | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw "Working tree is not clean. Commit your changes first or use -StagePaths with -CommitMessage."
    }
}

$remoteBefore = Invoke-StrictShaCheck -Remote $RemoteName -BranchName $Branch
$bootstrapMode = $false
if ([string]::IsNullOrWhiteSpace($remoteBefore)) {
    if (-not $AllowMainBootstrap) {
        throw "Could not read remote SHA for ${RemoteName}/${Branch}. Pass -AllowMainBootstrap if this is the first push."
    }
    $bootstrapMode = $true
}

$sha = (git rev-parse HEAD).Trim()
$remoteBeforeLabel = if ($bootstrapMode) { '<bootstrap>' } else { $remoteBefore }
Write-Output "REMOTE_BEFORE=$remoteBeforeLabel"

if (-not $bootstrapMode) {
    $remoteNow = Invoke-StrictShaCheck -Remote $RemoteName -BranchName $Branch
    if ($remoteNow -ne $remoteBefore) {
        throw "원격 브랜치가 푸시 시작 전에 변경되었습니다: $remoteBefore -> $remoteNow"
    }
}

if ($PSCmdlet.ShouldProcess("$RemoteName/$Branch", 'Push')) {
    git push $RemoteName ("HEAD:refs/heads/$Branch")
}

$remoteAfter = Invoke-StrictShaCheck -Remote $RemoteName -BranchName $Branch
if ([string]::IsNullOrWhiteSpace($remoteAfter)) {
    throw "원격 SHA 조회 실패: ${RemoteName}/${Branch}."
}
if ($remoteAfter -ne $sha) {
    throw "원격 SHA 불일치: expected=$sha actual=$remoteAfter"
}

Write-Output "PUSH_OK=$sha"
