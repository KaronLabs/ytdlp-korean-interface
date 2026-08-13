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
    $waited = New-Object System.Collections.Generic.List[int]
    $running = [pscustomobject]@{ Id = 41; HasExited = $false }
    $exited = [pscustomobject]@{ Id = 42; HasExited = $true }
    Stop-TrackedProcesses -Processes @($running, $exited) -StopAction { param($process) $stopped.Add($process.Id) } -WaitAction { param($process, $milliseconds) $waited.Add($process.Id); $true }
    Assert-Equal 1 $stopped.Count 'Only running fake processes should be stopped.'
    Assert-Equal 41 $stopped[0] 'The running fake process must be stopped.'
    Assert-Equal 1 $waited.Count 'A stopped process must be waited for before cleanup completes.'
    Assert-Equal 41 $waited[0] 'The running fake process must be waited for.'
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
        Assert-Equal 'part_file' $part.ReasonCode 'Part-file rejection must identify the stable reason code.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-FailureEvidenceAndSuccessCleanup {
    $root = New-FixtureRoot
    try {
        $evidence = Join-Path $root 'evidence'; [IO.Directory]::CreateDirectory($evidence) | Out-Null
        $failureWorkspace = Join-Path $root 'failed'; [IO.Directory]::CreateDirectory($failureWorkspace) | Out-Null
        Complete-SmokeWorkspace -Workspace $failureWorkspace -EvidenceDirectory $evidence -Succeeded:$false -ReasonCode 'fixture_failure'
        Assert-True (Test-Path -LiteralPath $failureWorkspace) 'Failed smoke workspace must be retained.'
        Assert-True (Test-Path -LiteralPath (Join-Path $evidence 'failure.json')) 'Failed smoke must retain evidence.'
        $successWorkspace = Join-Path $root 'success'; [IO.Directory]::CreateDirectory($successWorkspace) | Out-Null
        Complete-SmokeWorkspace -Workspace $successWorkspace -EvidenceDirectory $evidence -Succeeded:$true -ReasonCode 'ok'
        Assert-False (Test-Path -LiteralPath $successWorkspace) 'Successful smoke workspace must be cleaned up.'
        Assert-True (Test-Path -LiteralPath (Join-Path $evidence 'result.json')) 'Successful smoke must retain the result manifest.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-CleanupTimeoutStillWritesSanitizedFailureEvidence {
    $root = New-FixtureRoot
    try {
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $evidence = Join-Path $root 'evidence'
        try { Complete-SmokeRun -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$true -ReasonCode 'ok' -CleanupAction { throw 'process_cleanup_timeout' }; $threw = $false }
        catch { $threw = $_.Exception.Message -eq 'process_cleanup_timeout' }
        Assert-True $threw 'A cleanup timeout must fail the smoke after recording evidence.'
        $manifest = Get-Content -LiteralPath (Join-Path $evidence 'failure.json') -Raw | ConvertFrom-Json
        Assert-Equal 'process_cleanup_timeout' $manifest.reasonCode 'Cleanup timeout evidence must use the stable reason code.'
        Assert-False ($manifest.PSObject.Properties.Name -contains 'reason') 'Cleanup timeout evidence must not expose exception text.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeProcessFailuresMapToStableReasonCodes {
    foreach ($case in @(@('fixture_generation_failed', 'fixture failure'), @('ffprobe_failed', 'probe failure'))) {
        try { Invoke-SmokeProcess -ReasonCode $case[0] -Action { throw $case[1] } | Out-Null; $actual = 'no_failure' }
        catch { $actual = $_.Exception.Message }
        Assert-Equal $case[0] $actual 'Smoke process failure must preserve its stable reason code.'
    }
}

function Test-SmokeOutputRequiresFreshFiles {
    $root = New-FixtureRoot
    try {
        $output = Join-Path $root 'output'; [IO.Directory]::CreateDirectory($output) | Out-Null
        $mp3 = Join-Path $output 'stale.mp3'; [IO.File]::WriteAllText($mp3, 'stale', [Text.Encoding]::ASCII)
        $staleTime = [DateTime]::UtcNow.AddMinutes(-5)
        [IO.File]::SetCreationTimeUtc($mp3, $staleTime); [IO.File]::SetLastWriteTimeUtc($mp3, $staleTime)
        $started = [DateTime]::UtcNow
        $result = Test-SmokeOutput -OutputDirectory $output -StartedAtUtc $started -FfprobeAction { param($path) "codec_name=mp3`nduration=2.0" }
        Assert-False $result.Valid 'An output created before the smoke start must be rejected.'
        Assert-Equal 'stale_output' $result.ReasonCode 'Stale output must have a stable reason code.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-AutomationCompletionIsBoundToGuiUrlAndOutput {
    $root = New-FixtureRoot
    try {
        $output = Join-Path $root 'output'; [IO.Directory]::CreateDirectory($output) | Out-Null
        $url = 'http://127.0.0.1:18888/input.mp4'
        $good = [pscustomobject]@{ Completed = $true; GuiProcessId = 71; Url = $url; OutputDirectory = $output }
        Assert-True (Test-AutomationCompletion -Marker $good -GuiProcessId 71 -Url $url -OutputDirectory $output) 'Completion marker must bind GUI PID, URL, and output.'
        $bad = [pscustomobject]@{ Completed = $true; GuiProcessId = 72; Url = $url; OutputDirectory = $output }
        Assert-False (Test-AutomationCompletion -Marker $bad -GuiProcessId 71 -Url $url -OutputDirectory $output) 'Mismatched GUI PID must be rejected.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-ParentOverlapAndSanitizedEvidenceAreRejected {
    $root = New-FixtureRoot
    try {
        $parent = Join-Path $root 'parent'; $candidate = Join-Path $parent 'candidate'; [IO.Directory]::CreateDirectory($candidate) | Out-Null
        Assert-True (Test-PathOverlap -First $parent -Second $candidate) 'Nested candidate and parent roots must overlap.'
        $evidence = Join-Path $root 'evidence'; $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        Complete-SmokeWorkspace -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$false -ReasonCode 'gui_start_failed'
        $manifest = Get-Content -LiteralPath (Join-Path $evidence 'failure.json') -Raw | ConvertFrom-Json
        Assert-Equal 'gui_start_failed' $manifest.reasonCode 'Evidence must retain only the stable reason code.'
        Assert-Equal 'workspace' $manifest.workspaceId 'Evidence must contain the relative workspace identifier only.'
        Assert-False ($manifest.PSObject.Properties.Name -contains 'reason') 'Evidence must not expose exception text.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-DependencyArchiveAndRuntimeVerificationBoundaries {
    $manifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools/dependency-archives.json') -Raw | ConvertFrom-Json
    Assert-Equal 'ytdlp-interface dependencies.7z' $manifest.archives[0].name 'The reviewed dependency archive name must be fixed.'
    Assert-Equal '6D50D1F74978CFAB8E40439487D67EF21A4B43E31CFB00EE95D23AEDFC791BAE' $manifest.archives[0].sha256 'The reviewed dependency archive hash must be fixed.'
    Assert-True (Test-ArchiveEntrySafe -Entry 'nana/include/nana/gui.hpp' -ExpectedRoots @('bit7z', 'nana', 'libpng', 'libjpeg-turbo-3.1.2')) 'Expected dependency paths must be accepted.'
    Assert-False (Test-ArchiveEntrySafe -Entry '..\parent\overwrite' -ExpectedRoots @('bit7z')) 'Archive traversal must be rejected.'
    Assert-False (Test-ArchiveEntrySafe -Entry 'C:\absolute\overwrite' -ExpectedRoots @('bit7z')) 'Absolute archive paths must be rejected.'
    $entries = Get-ArchiveEntriesFromListing -Listing @('Path = C:\fixtures\ytdlp-interface dependencies.7z', 'Path = nana\include\nana\gui.hpp', 'Path = bit7z\include\bit7z\bit7z.hpp')
    Assert-Equal 2 $entries.Count 'The 7z archive header must not be treated as an extractable entry.'
    Assert-Equal 'nana\include\nana\gui.hpp' $entries[0] 'The first actual archive entry must remain after header removal.'
    $buildSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools/build-candidate.ps1') -Raw
    Assert-True ($buildSource -match 'Get-VerifiedParentRuntime') 'Candidate assembly must verify the parent runtime before copy.'
    Assert-True ($buildSource -match 'yt-dlp-provenance.json') 'Parent provenance must be required.'
    Assert-True ($buildSource -match 'Wait-LoopbackServer' -or (Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools/smoke-localhost.ps1') -Raw) -match 'Wait-LoopbackServer') 'Smoke must wait for loopback server readiness.'
}

function Test-CheckedProcessUsesExitCodeAndCapturesOutput {
    $shell = $env:ComSpec
    $ok = Invoke-CheckedProcess -FilePath $shell -Arguments @('/d', '/c', 'echo', 'fixture-process') -Name 'fixture process'
    Assert-Equal 0 $ok.ExitCode 'A successful child process must report its explicit ExitCode.'
    Assert-True ($ok.StandardOutput -match 'fixture-process') 'A successful child process must retain stdout.'
    Assert-Equal '"path with spaces"' (Quote-WindowsArgument 'path with spaces') 'Arguments with spaces must be quoted exactly once.'
    Assert-Equal 'plain' (Quote-WindowsArgument 'plain') 'Plain arguments must not be gratuitously quoted.'
    Assert-Equal '"say \"hello\""' (Quote-WindowsArgument 'say "hello"') 'Embedded quotes must be escaped for CreateProcess.'
    try { Invoke-CheckedProcess -FilePath $shell -Arguments @('/d', '/c', 'exit 7') -Name 'failing fixture process' | Out-Null; $threw = $false } catch { $threw = $true }
    Assert-True $threw 'A nonzero child ExitCode must fail without reading LASTEXITCODE.'
}

function Test-ReleaseX64DependencyPlanBuildsAndValidatesProductLibraries {
    $root = New-FixtureRoot
    try {
        $planCommand = Get-Command -Name Get-ReleaseX64DependencyPlan -ErrorAction SilentlyContinue
        $validateCommand = Get-Command -Name Test-ReleaseX64DependencyLibraries -ErrorAction SilentlyContinue
        Assert-True ($null -ne $planCommand) 'Candidate build must declare the Release x64 dependency plan.'
        Assert-True ($null -ne $validateCommand) 'Candidate build must validate the Release x64 libraries before product MSBuild.'
        if ($null -eq $planCommand -or $null -eq $validateCommand) { return }

        $plan = Get-ReleaseX64DependencyPlan -SourceRoot $root
        Assert-Equal 4 $plan.Count 'The Release x64 plan must build all four source dependencies.'
        Assert-Equal 'bit7z64.lib' (Split-Path -Leaf $plan[0].LibraryPath) 'bit7z must produce the product linker library name.'
        Assert-Equal 'nana_v143_Release_x64.lib' (Split-Path -Leaf $plan[1].LibraryPath) 'Nana must be built with the v143 linker library name.'
        Assert-Equal 'libpng.lib' (Split-Path -Leaf $plan[2].LibraryPath) 'libpng must produce the product linker library name.'
        Assert-Equal 'turbojpeg-static.lib' (Split-Path -Leaf $plan[3].LibraryPath) 'libjpeg-turbo must produce the product linker library name.'
        Assert-False (Test-ReleaseX64DependencyLibraries -Plan $plan) 'Missing Release x64 libraries must block product MSBuild.'
        foreach ($dependency in $plan) {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $dependency.LibraryPath)) | Out-Null
            [IO.File]::WriteAllText($dependency.LibraryPath, 'fixture', [Text.Encoding]::ASCII)
        }
        Assert-True (Test-ReleaseX64DependencyLibraries -Plan $plan) 'All four expected Release x64 libraries must satisfy the pre-product gate.'
        Assert-True ($plan[0].Arguments -contains '/p:PlatformToolset=v143') 'bit7z must be built with the installed v143 toolset.'
        Assert-True ($plan[1].Arguments -contains '/p:PlatformToolset=v143') 'Nana must be built with the installed v143 toolset.'
        Assert-True ($plan[2].Arguments -contains '/p:PlatformToolset=v143') 'libpng must be built with the installed v143 toolset.'
        Assert-True ($plan[3].Arguments -contains '-T') 'libjpeg-turbo CMake generation must select a toolset.'
        Assert-True ($plan[3].Arguments -contains 'v143') 'libjpeg-turbo CMake generation must select v143.'
        $buildSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools/build-candidate.ps1') -Raw
        Assert-True ($buildSource.LastIndexOf('Invoke-ReleaseX64Dependencies') -lt $buildSource.LastIndexOf("-Name 'Release x64 MSBuild'")) 'All dependency builds and library validation must complete before product MSBuild.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-CandidateRootsAreUniqueAndContained
Test-LocalhostOnlyUrls
Test-FakeProcessesAreCleanedUp
Test-FinalMp3AndPartRejection
Test-FailureEvidenceAndSuccessCleanup
Test-CleanupTimeoutStillWritesSanitizedFailureEvidence
Test-SmokeOutputRequiresFreshFiles
Test-AutomationCompletionIsBoundToGuiUrlAndOutput
Test-ParentOverlapAndSanitizedEvidenceAreRejected
Test-DependencyArchiveAndRuntimeVerificationBoundaries
Test-CheckedProcessUsesExitCodeAndCapturesOutput
Test-SmokeProcessFailuresMapToStableReasonCodes
Test-ReleaseX64DependencyPlanBuildsAndValidatesProductLibraries

if ($script:failures.Count -ne 0) { $script:failures | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Output 'smoke-localhost fixture tests passed.'
