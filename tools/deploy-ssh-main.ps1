[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $RepoRoot = (Join-Path $PSScriptRoot '..'),
    [string[]] $StagePaths = @(),
    [string] $CommitMessage,
    [switch] $AllowMainBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CanonicalRemoteName = 'origin'
$CanonicalRemoteUrl = 'git@github.com:KaronLabs/ytdlp-korean-interface.git'
$CanonicalBranch = 'main'
$ExpectedGitHubLogin = 'KaronLabs'

function Invoke-GitStrict {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $output = @(& git @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $rendered = $Arguments -join ' '
        $details = ($output | Out-String).Trim()
        throw "git command failed (exit=$exitCode): git $rendered`n$details"
    }
    return $output
}

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

function Assert-MainBranch {
    $output = @(Invoke-GitStrict -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD'))
    $current = ($output | Out-String).Trim()
    if ($current -ne $CanonicalBranch) {
        throw "Deployment requires current branch '$CanonicalBranch'. Found: '$current'."
    }
}

function Assert-CanonicalRemote {
    $fetchUrls = @(Invoke-GitStrict -Arguments @('remote', 'get-url', '--all', $CanonicalRemoteName))
    $fetchUrls = @($fetchUrls | ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ })
    if ($fetchUrls.Count -ne 1 -or $fetchUrls[0] -ne $CanonicalRemoteUrl) {
        throw "origin fetch URL must be exactly '$CanonicalRemoteUrl'. Found: '$($fetchUrls -join ', ')'."
    }

    $pushUrls = @(Invoke-GitStrict -Arguments @('remote', 'get-url', '--push', '--all', $CanonicalRemoteName))
    $pushUrls = @($pushUrls | ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ })
    if ($pushUrls.Count -ne 1 -or $pushUrls[0] -ne $CanonicalRemoteUrl) {
        throw "origin push URL must be exactly '$CanonicalRemoteUrl'. Found: '$($pushUrls -join ', ')'."
    }
}

function Invoke-StrictShaCheck {
    $ref = "refs/heads/$CanonicalBranch"
    $output = @(Invoke-GitStrict -Arguments @('ls-remote', $CanonicalRemoteUrl, $ref))
    $lines = @($output | ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ })
    if ($lines.Count -eq 0) { return $null }
    if ($lines.Count -ne 1) { throw "Unexpected ls-remote response count for ${ref}: $($lines.Count)" }

    $match = [regex]::Match($lines[0], '^([0-9a-fA-F]{40})\s+refs/heads/main$')
    if (-not $match.Success) { throw "Malformed ls-remote response for ${ref}: $($lines[0])" }
    return $match.Groups[1].Value.ToLowerInvariant()
}

function Invoke-SshAuthCheck {
    $msg = (& ssh -T git@github.com 2>&1 | Out-String).Trim()
    $expected = "(?m)^Hi\s+$([regex]::Escape($ExpectedGitHubLogin))!\s+You've successfully authenticated"
    if ($msg -notmatch $expected) {
        throw "SSH identity is not verified as GitHub login '$ExpectedGitHubLogin': $msg"
    }
}

function Get-StagedPaths {
    $output = @(Invoke-GitStrict -Arguments @('diff', '--cached', '--name-only'))
    return @($output | ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ })
}

function Resolve-LiteralStagePath {
    param(
        [Parameter(Mandatory = $true)] [string] $RootPath,
        [Parameter(Mandatory = $true)] [string] $Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) { throw 'StagePaths cannot contain an empty path.' }
    if ($Candidate.StartsWith(':')) { throw "Git pathspec magic is not allowed in StagePaths: $Candidate" }
    if ([IO.Path]::IsPathRooted($Candidate)) { throw "StagePaths must be repository-relative: $Candidate" }

    $full = [IO.Path]::GetFullPath((Join-Path $RootPath $Candidate))
    $rootPrefix = $RootPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "StagePaths must stay inside the repository: $Candidate"
    }

    $relative = [IO.Path]::GetRelativePath($RootPath, $full).Replace('\', '/')
    if ($relative -eq '.git' -or $relative.StartsWith('.git/', [StringComparison]::OrdinalIgnoreCase)) {
        throw "StagePaths cannot target .git metadata: $Candidate"
    }
    if ((Test-Path -LiteralPath $full) -and (Test-Path -LiteralPath $full -PathType Container)) {
        throw "StagePaths must name explicit files, not directories: $Candidate"
    }

    return $relative
}

Set-Location -LiteralPath (Resolve-RepoRoot)
$rootOutput = @(Invoke-GitStrict -Arguments @('rev-parse', '--show-toplevel'))
$root = ($rootOutput | Out-String).Trim()
Assert-Root -RootPath $root
Assert-MainBranch
Invoke-SshAuthCheck
Assert-CanonicalRemote

if (($StagePaths.Count -gt 0) -and [string]::IsNullOrWhiteSpace($CommitMessage)) {
    throw 'CommitMessage is required when StagePaths is provided.'
}
if (($StagePaths.Count -eq 0) -and (-not [string]::IsNullOrWhiteSpace($CommitMessage))) {
    throw 'StagePaths is required when CommitMessage is provided.'
}

if ($StagePaths.Count -gt 0) {
    $alreadyStaged = @(Get-StagedPaths)
    if ($alreadyStaged.Count -gt 0) {
        throw "Git index must be clean before -StagePaths deployment. Already staged: $($alreadyStaged -join ', ')"
    }

    $relativePaths = @()
    foreach ($candidate in $StagePaths) {
        $relativePaths += Resolve-LiteralStagePath -RootPath $root -Candidate $candidate
    }
    $relativePaths = @($relativePaths | Sort-Object -Unique)

    $literalPathspecs = @($relativePaths | ForEach-Object { ":(literal)$_" })
    $null = Invoke-GitStrict -Arguments (@('add', '--') + $literalPathspecs)

    $staged = @(Get-StagedPaths | Sort-Object -Unique)
    $unexpected = @($staged | Where-Object { $_ -notin $relativePaths })
    if ($unexpected.Count -gt 0) {
        throw "Unexpected staged paths after git add: $($unexpected -join ', ')"
    }
    if ($staged.Count -eq 0) {
        throw 'StagePaths produced no staged changes; refusing empty deployment commit.'
    }

    $null = Invoke-GitStrict -Arguments @('commit', '-m', $CommitMessage)
    $remainingStaged = @(Get-StagedPaths)
    if ($remainingStaged.Count -gt 0) {
        throw "Git index is not clean after commit: $($remainingStaged -join ', ')"
    }
}
else {
    $statusOutput = @(Invoke-GitStrict -Arguments @('status', '--short'))
    $status = ($statusOutput | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw "Working tree is not clean. Commit your changes first or use -StagePaths with -CommitMessage."
    }
}

$remoteBefore = Invoke-StrictShaCheck
$bootstrapMode = $false
if ([string]::IsNullOrWhiteSpace($remoteBefore)) {
    if (-not $AllowMainBootstrap) {
        throw "Could not read remote SHA for origin/main. Pass -AllowMainBootstrap only for an approved first push."
    }
    $bootstrapMode = $true
}

$shaOutput = @(Invoke-GitStrict -Arguments @('rev-parse', '--verify', 'HEAD^{commit}'))
$sha = ($shaOutput | Out-String).Trim().ToLowerInvariant()
if ($sha -notmatch '^[0-9a-f]{40}$') { throw "Invalid local commit SHA: $sha" }

$remoteBeforeLabel = if ($bootstrapMode) { '<bootstrap>' } else { $remoteBefore }
Write-Output "REMOTE_BEFORE=$remoteBeforeLabel"
Write-Output "LOCAL_SHA=$sha"

if (-not $bootstrapMode) {
    $remoteNow = Invoke-StrictShaCheck
    if ($remoteNow -ne $remoteBefore) {
        throw "원격 브랜치가 푸시 시작 전에 변경되었습니다: $remoteBefore -> $remoteNow"
    }
}

if (-not $PSCmdlet.ShouldProcess("$CanonicalRemoteUrl/$CanonicalBranch", "Push exact commit $sha")) {
    Write-Output "PUSH_SKIPPED=$sha"
    return
}

$null = Invoke-GitStrict -Arguments @('push', $CanonicalRemoteUrl, "${sha}:refs/heads/$CanonicalBranch")

$remoteAfter = Invoke-StrictShaCheck
if ([string]::IsNullOrWhiteSpace($remoteAfter)) {
    throw "원격 SHA 조회 실패: origin/main."
}
if ($remoteAfter -ne $sha) {
    throw "원격 SHA 불일치: expected=$sha actual=$remoteAfter"
}

Write-Output "REMOTE_AFTER=$remoteAfter"
Write-Output "PUSH_OK=$sha"
