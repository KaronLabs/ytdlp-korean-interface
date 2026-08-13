$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repositoryRoot 'tools/build-candidate.ps1')
. (Join-Path $repositoryRoot 'tools/smoke-localhost.ps1')

$script:failures = New-Object System.Collections.Generic.List[string]
function Assert-True { param([bool] $Condition, [string] $Message) if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-False { param([bool] $Condition, [string] $Message) if ($Condition) { $script:failures.Add($Message) } }
function Assert-Equal { param($Expected, $Actual, [string] $Message) if ($Expected -ne $Actual) { $script:failures.Add("$Message Expected=[$Expected] Actual=[$Actual]") } }
function New-FixtureRoot { $path = Join-Path ([IO.Path]::GetTempPath()) ('localhost-smoke-tests-' + [Guid]::NewGuid().ToString('N')); [IO.Directory]::CreateDirectory($path) | Out-Null; return $path }

function Test-CandidateRootsAreUniqueAndContained {
    $root = New-FixtureRoot
    try {
        $one = New-CandidateRoot -BaseDirectory $root
        $two = New-CandidateRoot -BaseDirectory $root
        Assert-True (Test-PathContained -Root $root -Path $one) 'Candidate one must be contained by its base root.'
        Assert-True (Test-PathContained -Root $root -Path $two) 'Candidate two must be contained by its base root.'
        Assert-False ($one -eq $two) 'Candidate roots must be unique.'
        Assert-False (Test-PathContained -Root $root -Path (Join-Path $root '..\escape')) 'Traversal must not be treated as contained.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-LocalhostOnlyUrls {
    Assert-True (Test-LocalhostUrl -Url 'http://127.0.0.1:18888/input.mp4') '127.0.0.1 URL must be accepted.'
    Assert-False (Test-LocalhostUrl -Url 'http://localhost:18888/input.mp4') 'Hostname localhost must not substitute for the explicit loopback bind.'
    Assert-False (Test-LocalhostUrl -Url 'http://0.0.0.0:18888/input.mp4') 'Wildcard binds must be rejected.'
    Assert-False (Test-LocalhostUrl -Url 'https://example.com/input.mp4') 'External URLs must be rejected.'
}

function Test-FakeProcessesAreCleanedUp {
    $stopped = New-Object System.Collections.Generic.List[int]
    $running = [pscustomobject]@{ Id = 41; HasExited = $false }
    $exited = [pscustomobject]@{ Id = 42; HasExited = $true }
    Stop-TrackedProcesses -Processes @($running, $exited) -StopAction { param($process) $stopped.Add($process.Id) } 
    Assert-Equal 1 $stopped.Count 'Only running fake processes should be stopped.'
    Assert-Equal 41 $stopped[0] 'The running fake process must be stopped.'
}

function Test-FinalMp3AndPartRejection {
    $root = New-FixtureRoot
    try {
        $output = Join-Path $root 'output'; [IO.Directory]::CreateDirectory($output) | Out-Null
        $mp3 = Join-Path $output 'result.mp3'; [IO.File]::WriteAllText($mp3, 'fixture', [Text.Encoding]::ASCII)
        $ok = Test-SmokeOutput -OutputDirectory $output -FfprobeAction { param($path) "codec_name=mp3`nduration=2.0" }
        Assert-True $ok.Valid 'A nonempty MP3 with positive MP3 probe output must pass.'
        [IO.File]::WriteAllText((Join-Path $output 'result.mp3.part'), 'partial', [Text.Encoding]::ASCII)
        $part = Test-SmokeOutput -OutputDirectory $output -FfprobeAction { param($path) "codec_name=mp3`nduration=2.0" }
        Assert-False $part.Valid 'A .part file must reject the result.'
        Assert-True ($part.Reason -match 'part') 'Part-file rejection must identify the reason.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-FailureEvidenceAndSuccessCleanup {
    $root = New-FixtureRoot
    try {
        $evidence = Join-Path $root 'evidence'; [IO.Directory]::CreateDirectory($evidence) | Out-Null
        $failureWorkspace = Join-Path $root 'failed'; [IO.Directory]::CreateDirectory($failureWorkspace) | Out-Null
        Complete-SmokeWorkspace -Workspace $failureWorkspace -EvidenceDirectory $evidence -Succeeded:$false -Reason 'fixture failure'
        Assert-True (Test-Path -LiteralPath $failureWorkspace) 'Failed smoke workspace must be retained.'
        Assert-True (Test-Path -LiteralPath (Join-Path $evidence 'failure.json')) 'Failed smoke must retain evidence.'
        $successWorkspace = Join-Path $root 'success'; [IO.Directory]::CreateDirectory($successWorkspace) | Out-Null
        Complete-SmokeWorkspace -Workspace $successWorkspace -EvidenceDirectory $evidence -Succeeded:$true -Reason 'fixture success'
        Assert-False (Test-Path -LiteralPath $successWorkspace) 'Successful smoke workspace must be cleaned up.'
        Assert-True (Test-Path -LiteralPath (Join-Path $evidence 'result.json')) 'Successful smoke must retain the result manifest.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-CandidateRootsAreUniqueAndContained
Test-LocalhostOnlyUrls
Test-FakeProcessesAreCleanedUp
Test-FinalMp3AndPartRejection
Test-FailureEvidenceAndSuccessCleanup

if ($script:failures.Count -ne 0) { $script:failures | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Output 'smoke-localhost fixture tests passed.'
