$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

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
        Assert-True ($null -ne ('System.IO.Compression.ZipFile' -as [type])) 'zipfile_type_unavailable'
        [void](Invoke-TestGit $case.Source @('checkout', '--detach', '-q'))
        $expectedCommit = Invoke-TestGit $case.Source @('rev-parse', '--verify', 'HEAD^{commit}')
        $expectedTree = Invoke-TestGit $case.Source @('rev-parse', '--verify', ($expectedCommit + '^{tree}'))
        $attestation = Get-SourceAttestation -SourceRoot $case.Source -GitPath $script:GitPath
        $trackedEntries = @(Get-GitTreeEntries -SourceRoot $case.Source -GitPath $script:GitPath -Commit $attestation.commit)
        $trackedPaths = @($trackedEntries | ForEach-Object { $_.Path })
        $workspace = Join-Path $case.Root 'clean-workspace'
        [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $immutableSource = New-IsolatedBuildSource -SourceRoot $case.Source -WorkspaceRoot $workspace -DependencyRoots @('__none__') -Commit $attestation.commit -GitPath $script:GitPath
        $input = Get-SourceInputAttestation -SourceRoot $immutableSource -Commit $attestation.commit -StatusPorcelain '' -TrackedPaths $trackedPaths
        $attestation['treeSha256'] = $input.treeSha256
        $attestation['trackedFileCount'] = $input.trackedFileCount
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
        $preferenceBefore = $ErrorActionPreference
        $caught = $null
        try {
            Invoke-BuildCandidate -SourceRoot $case.Source -ParentRuntime $case.Parent -CandidateBase $case.CandidateBase -DependencyArchiveDirectory $case.DependencyArchives -RuntimeArchiveDirectory $case.RuntimeArchives
        } catch { $caught = $_ }
        Assert-True ($null -ne $caught) 'non-Git source did not fail'
        Assert-Equal 'source_input_invalid' $caught.Exception.Message 'non-Git source escaped the controlled error contract'
        Assert-True ($caught.ToString() -notmatch 'fatal:') 'non-Git source leaked native Git stderr'
        Assert-Equal $preferenceBefore $ErrorActionPreference 'non-Git source changed the caller error preference'
        Assert-True (-not (Test-Path -LiteralPath $case.CandidateBase)) 'non-Git source produced candidate output'
    }
    finally { Remove-TestCase $case }
}

function Invoke-TestRaceMutation {
    param(
        [Parameter(Mandatory)] [string] $SourceRoot,
        [Parameter(Mandatory)] [string] $SentinelPath,
        [Parameter(Mandatory)] [string] $StagedPath,
        [Parameter(Mandatory)] [string] $UntrackedPath
    )

    Write-TestUtf8 $SentinelPath "mutated tracked bytes`n"
    Write-TestUtf8 $StagedPath "staged after clean measurement`n"
    Write-TestUtf8 $UntrackedPath "untracked after clean measurement`n"
    [void](Invoke-TestGit $SourceRoot @('add', '--', $SentinelPath, $StagedPath))
}

function Invoke-TestSourceMaterialization {
    param(
        [Parameter(Mandatory)] [string] $SourceRoot,
        [Parameter(Mandatory)] [string] $WorkspaceRoot,
        [Parameter(Mandatory)] [string] $Commit,
        [Parameter(Mandatory)] [string[]] $TrackedPaths
    )

    $parameters = @{
        SourceRoot = $SourceRoot
        WorkspaceRoot = $WorkspaceRoot
        DependencyRoots = @('__none__')
    }
    $materializer = Get-Command New-IsolatedBuildSource -CommandType Function
    if ($materializer.Parameters.ContainsKey('Commit')) {
        $parameters.Commit = $Commit
        $parameters.GitPath = $script:GitPath
    } else {
        $parameters.TrackedPaths = $TrackedPaths
    }

    return New-IsolatedBuildSource @parameters
}

function New-TestZipArchive {
    param(
        [Parameter(Mandatory)] [string] $ArchivePath,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Entries
    )

    $archive = [IO.Compression.ZipFile]::Open($ArchivePath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($item in $Entries.GetEnumerator()) {
            $entry = $archive.CreateEntry([string] $item.Key)
            $stream = $entry.Open()
            try {
                $bytes = [Text.UTF8Encoding]::new($false).GetBytes([string] $item.Value)
                $stream.Write($bytes, 0, $bytes.Length)
            } finally {
                $stream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
}

Invoke-Test 'immutable materialization resists a post-attestation source and index race' {
    $case = New-TestCase -GitRepository
    $originalSourceInputAttestation = ${function:Get-SourceInputAttestation}
    try {
        $sentinelRelative = 'race sentinel.txt'
        $sentinelPath = Join-Path $case.Source $sentinelRelative
        $stagedPath = Join-Path $case.Source 'staged-only.txt'
        $untrackedPath = Join-Path $case.Source 'untracked-only.txt'

        Write-TestUtf8 $sentinelPath "original tracked bytes`n"
        [void](Invoke-TestGit $case.Source @('add', '--', $sentinelPath))
        [void](Invoke-TestGit $case.Source @('commit', '-m', 'add race sentinels'))

        $capturedCommit = (Invoke-TestGit $case.Source @('rev-parse', 'HEAD')).Trim()
        $trackedPaths = @(Get-GitTrackedPaths -SourceRoot $case.Source -GitPath $script:GitPath)
        $expectedSentinel = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sentinelPath))

        $script:RaceSourceRoot = [IO.Path]::GetFullPath($case.Source)
        $script:RaceSentinelPath = $sentinelPath
        $script:RaceStagedPath = $stagedPath
        $script:RaceUntrackedPath = $untrackedPath
        $script:RaceMutationApplied = $false
        $script:OriginalSourceInputAttestation = $originalSourceInputAttestation

        Set-Item -LiteralPath Function:\Get-SourceInputAttestation -Value {
            param(
                [Parameter(Mandatory)] [string] $SourceRoot,
                [Parameter(Mandatory)] [string] $Commit,
                [AllowEmptyString()] [string] $StatusPorcelain,
                [Parameter(Mandatory)] [string[]] $TrackedPaths
            )

            if (-not $script:RaceMutationApplied -and
                [IO.Path]::GetFullPath($SourceRoot) -ieq $script:RaceSourceRoot) {
                Invoke-TestRaceMutation `
                    -SourceRoot $script:RaceSourceRoot `
                    -SentinelPath $script:RaceSentinelPath `
                    -StagedPath $script:RaceStagedPath `
                    -UntrackedPath $script:RaceUntrackedPath
                $script:RaceMutationApplied = $true
            }

            return & $script:OriginalSourceInputAttestation @PSBoundParameters
        }

        try {
            $sourceAttestation = Get-SourceAttestation `
                -SourceRoot $case.Source `
                -GitPath $script:GitPath
        } finally {
            Set-Item -LiteralPath Function:\Get-SourceInputAttestation -Value $originalSourceInputAttestation
        }

        if (-not $script:RaceMutationApplied) {
            Invoke-TestRaceMutation `
                -SourceRoot $case.Source `
                -SentinelPath $sentinelPath `
                -StagedPath $stagedPath `
                -UntrackedPath $untrackedPath
            $script:RaceMutationApplied = $true
        }

        Assert-True $script:RaceMutationApplied 'The race mutation did not run.'
        Assert-Equal $capturedCommit $sourceAttestation.commit 'The captured commit changed during the race.'

        $workspace = Join-Path $case.Root 'race-workspace'
        [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $isolated = Invoke-TestSourceMaterialization `
            -SourceRoot $case.Source `
            -WorkspaceRoot $workspace `
            -Commit $sourceAttestation.commit `
            -TrackedPaths $trackedPaths

        Assert-Equal $expectedSentinel ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $isolated $sentinelRelative)))) 'The isolated source did not preserve the captured sentinel blob.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $isolated 'staged-only.txt'))) 'The isolated source consumed the raced index entry.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $isolated 'untracked-only.txt'))) 'The isolated source consumed untracked worktree bytes.'

        $isolatedInput = & $originalSourceInputAttestation `
            -SourceRoot $isolated `
            -Commit $sourceAttestation.commit `
            -StatusPorcelain '' `
            -TrackedPaths $trackedPaths
        $mutatedInput = & $originalSourceInputAttestation `
            -SourceRoot $case.Source `
            -Commit $sourceAttestation.commit `
            -StatusPorcelain '' `
            -TrackedPaths $trackedPaths
        Assert-True ($isolatedInput.treeSha256 -ne $mutatedInput.treeSha256) 'The immutable export matched raced worktree bytes.'
    } finally {
        Set-Item -LiteralPath Function:\Get-SourceInputAttestation -Value $originalSourceInputAttestation
        Remove-Variable -Scope Script -Name RaceSourceRoot, RaceSentinelPath, RaceStagedPath, RaceUntrackedPath, RaceMutationApplied, OriginalSourceInputAttestation -ErrorAction SilentlyContinue
        Remove-TestCase $case
    }
}

Invoke-Test 'immutable materialization preserves tracked paths with spaces and UTF-8' {
    $case = New-TestCase -GitRepository
    try {
        $directoryRelative = 'directory with spaces'
        $fileName = 'utf8-' + [string][char]0xD55C + [string][char]0xAE00 + '.txt'
        $relativePath = $directoryRelative + '/' + $fileName
        $sourcePath = Join-Path (Join-Path $case.Source $directoryRelative) $fileName
        [IO.Directory]::CreateDirectory((Split-Path -Parent $sourcePath)) | Out-Null
        Write-TestUtf8 $sourcePath "exact UTF-8 path bytes`n"
        [void](Invoke-TestGit $case.Source @('add', '--', $sourcePath))
        [void](Invoke-TestGit $case.Source @('commit', '-m', 'add UTF-8 path'))

        $commit = (Invoke-TestGit $case.Source @('rev-parse', 'HEAD')).Trim()
        $trackedPaths = @(Get-GitTrackedPaths -SourceRoot $case.Source -GitPath $script:GitPath)
        $expected = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourcePath))
        $workspace = Join-Path $case.Root 'utf8-workspace'
        [IO.Directory]::CreateDirectory($workspace) | Out-Null

        $isolated = Invoke-TestSourceMaterialization -SourceRoot $case.Source -WorkspaceRoot $workspace -Commit $commit -TrackedPaths $trackedPaths
        Assert-Equal $expected ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $isolated $relativePath)))) 'The isolated source changed a tracked UTF-8 path blob.'
    } finally {
        Remove-TestCase $case
    }
}

Invoke-Test 'source export rejects a preexisting destination without changing it' {
    $case = New-TestCase -GitRepository
    try {
        $commit = (Invoke-TestGit $case.Source @('rev-parse', 'HEAD')).Trim()
        $trackedPaths = @(Get-GitTrackedPaths -SourceRoot $case.Source -GitPath $script:GitPath)
        $workspace = Join-Path $case.Root 'collision-workspace'
        $destination = Join-Path $workspace 'source'
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        $marker = Join-Path $destination 'owner-marker.txt'
        Write-TestUtf8 $marker 'owner data'

        Assert-Throws {
            Invoke-TestSourceMaterialization -SourceRoot $case.Source -WorkspaceRoot $workspace -Commit $commit -TrackedPaths $trackedPaths
        } 'source_export_destination_exists'
        Assert-Equal 'owner data' ([IO.File]::ReadAllText($marker)) 'The collision path was modified.'
    } finally {
        Remove-TestCase $case
    }
}

Invoke-Test 'source export fails closed when git cannot export the captured commit' {
    $case = New-TestCase -GitRepository
    try {
        $commit = (Invoke-TestGit $case.Source @('rev-parse', 'HEAD')).Trim()
        $trackedPaths = @(Get-GitTrackedPaths -SourceRoot $case.Source -GitPath $script:GitPath)
        $workspace = Join-Path $case.Root 'failed-export-workspace'
        [IO.Directory]::CreateDirectory($workspace) | Out-Null

        Assert-Throws {
            Invoke-TestSourceMaterialization -SourceRoot $case.Source -WorkspaceRoot $workspace -Commit ('f' * 40) -TrackedPaths $trackedPaths
        } 'source_export_failed'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $workspace 'source'))) 'A failed export left a source destination.'
    } finally {
        Remove-TestCase $case
    }
}

Invoke-Test 'source archive rejects malformed bytes and removes partial output' {
    $case = New-TestCase
    try {
        $archivePath = Join-Path $case.Root 'malformed.zip'
        [IO.File]::WriteAllBytes($archivePath, [byte[]] @(1, 2, 3, 4))
        $destination = Join-Path $case.Root 'malformed-output'

        Assert-Throws {
            Expand-GitSourceArchive -ArchivePath $archivePath -DestinationRoot $destination -TrackedEntries @()
        } 'source_export_invalid'
        Assert-True (-not (Test-Path -LiteralPath $destination)) 'A malformed archive left partial output.'
    } finally {
        Remove-TestCase $case
    }
}

Invoke-Test 'source archive rejects path traversal without writing outside destination' {
    $case = New-TestCase
    try {
        $archivePath = Join-Path $case.Root 'traversal.zip'
        New-TestZipArchive -ArchivePath $archivePath -Entries ([ordered] @{ '../escape.txt' = 'escape' })
        $destination = Join-Path $case.Root 'traversal-output'

        Assert-Throws {
            Expand-GitSourceArchive -ArchivePath $archivePath -DestinationRoot $destination -TrackedEntries @()
        } 'source_export_path_invalid'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.Root 'escape.txt'))) 'Archive traversal wrote outside the destination.'
        Assert-True (-not (Test-Path -LiteralPath $destination)) 'Archive traversal left partial output.'
    } finally {
        Remove-TestCase $case
    }
}

Invoke-Test 'source archive rejects bytes that do not match the captured Git blob' {
    $case = New-TestCase -GitRepository
    try {
        $relativePath = 'blob with spaces.txt'
        $sourcePath = Join-Path $case.Source $relativePath
        Write-TestUtf8 $sourcePath 'captured blob'
        [void](Invoke-TestGit $case.Source @('add', '--', $sourcePath))
        [void](Invoke-TestGit $case.Source @('commit', '-m', 'add blob sentinel'))
        $commit = (Invoke-TestGit $case.Source @('rev-parse', 'HEAD')).Trim()
        $objectId = (Invoke-TestGit $case.Source @('rev-parse', ('{0}:{1}' -f $commit, $relativePath))).Trim()
        $archivePath = Join-Path $case.Root 'blob-mismatch.zip'
        New-TestZipArchive -ArchivePath $archivePath -Entries ([ordered] @{ $relativePath = 'substituted bytes' })
        $destination = Join-Path $case.Root 'blob-mismatch-output'
        $entry = [pscustomobject] @{ Path = $relativePath; ObjectId = $objectId; Mode = '100644' }

        Assert-Throws {
            Expand-GitSourceArchive -ArchivePath $archivePath -DestinationRoot $destination -TrackedEntries @($entry)
        } 'source_export_blob_mismatch'
        Assert-True (-not (Test-Path -LiteralPath $destination)) 'A blob mismatch left partial output.'
    } finally {
        Remove-TestCase $case
    }
}

Invoke-Test 'caller cannot supply application provenance fields' {
    $parameters = (Get-Command Invoke-BuildCandidate).Parameters.Keys
    Assert-True ($parameters -notcontains 'ApplicationSourceCommit') 'builder accepts a spoofed application source commit'
    Assert-True ($parameters -notcontains 'ApplicationSourceTree') 'builder accepts a spoofed application source tree'
}

if ($script:Failures -gt 0) { throw "$($script:Failures) of $($script:Tests) candidate provenance tests failed." }
Write-Host "All $($script:Tests) candidate provenance tests passed."
exit 0
