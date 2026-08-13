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

function New-FixtureBuildAttestation {
    return [ordered]@{
        source = [ordered]@{ commit = ('1' * 40); dirty = $false; treeSha256 = ('2' * 64); trackedFileCount = 1 }
        dependencyArchive = [ordered]@{ name = 'dependencies.7z'; sha256 = ('3' * 64) }
        linkerInputs = @(
            [ordered]@{ name = 'bit7z'; library = 'bit7z64.lib'; sha256 = ('4' * 64); length = 1 },
            [ordered]@{ name = 'Nana'; library = 'nana_v143_Release_x64.lib'; sha256 = ('B' * 64); length = 1 },
            [ordered]@{ name = 'libpng'; library = 'libpng.lib'; sha256 = ('C' * 64); length = 1 },
            [ordered]@{ name = 'libjpeg-turbo'; library = 'turbojpeg-static.lib'; sha256 = ('D' * 64); length = 1 }
        )
        toolchain = @(
            [ordered]@{ name = 'msbuild'; sha256 = ('5' * 64); version = '1' },
            [ordered]@{ name = 'cmake'; sha256 = ('6' * 64); version = '1' },
            [ordered]@{ name = 'cl'; sha256 = ('7' * 64); version = '1' },
            [ordered]@{ name = 'link'; sha256 = ('8' * 64); version = '1' },
            [ordered]@{ name = 'rc'; sha256 = ('9' * 64); version = '1' },
            [ordered]@{ name = 'windows-sdk'; sha256 = ('A' * 64); version = '10.0.1' }
        )
        commands = @(
            'bit7z Release x64 build', 'Nana Release x64 build', 'libpng Release x64 build',
            'libjpeg-turbo Release x64 configure', 'libjpeg-turbo Release x64 build', 'Release x64 MSBuild'
        ) | ForEach-Object {
            $executable = if ($_ -like 'libjpeg-turbo*') { 'cmake.exe' } else { 'MSBuild.exe' }
            $msbuild = @('/m', '/t:Build', '/p:Configuration=Release', '/p:Platform=x64', '/p:PlatformToolset=v143', '/p:ImportDirectoryBuildProps=false', '/p:ImportDirectoryBuildTargets=false', '/p:UserRootDir=<hermetic-user-root>\', '/p:VCToolsVersion=14.40.1', '/p:WindowsTargetPlatformVersion=10.0.1')
            $arguments = switch ($_) {
                'bit7z Release x64 build' { @('<source>\bit7z\bit7z.sln') + $msbuild }
                'Nana Release x64 build' { @('<source>\nana\build\vc2022\nana.sln') + $msbuild }
                'libpng Release x64 build' { @('<source>\libpng\libpng.sln') + $msbuild + @('/p:OutDir=<source>\libpng\x64\Release\') }
                'libjpeg-turbo Release x64 configure' { @('-S', '<source>\libjpeg-turbo-3.1.2', '-B', '<source>\libjpeg-turbo-3.1.2\out\build\x64-Release', '-G', 'Visual Studio 17 2022', '-A', 'x64', '-T', 'v143', '-DCMAKE_VS_GLOBALS=ImportDirectoryBuildProps=false;ImportDirectoryBuildTargets=false;UserRootDir=<hermetic-user-root>\;VCToolsVersion=14.40.1;WindowsTargetPlatformVersion=10.0.1', '-DENABLE_SHARED=OFF', '-DENABLE_STATIC=ON', '-DWITH_TURBOJPEG=ON', '-DWITH_CRT_DLL=OFF', '-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE=<source>\libjpeg-turbo-3.1.2\out\build\x64-Release') }
                'libjpeg-turbo Release x64 build' { @('--build', '<source>\libjpeg-turbo-3.1.2\out\build\x64-Release', '--config', 'Release', '--target', 'turbojpeg-static', '--') + $msbuild }
                'Release x64 MSBuild' { @('<source>\ytdlp-interface\ytdlp-interface.sln') + $msbuild }
            }
            [ordered]@{
                name = $_; executable = $executable; arguments = $arguments
                workingDirectory = '<source>'; effectiveProperties = [ordered]@{
                    Configuration = 'Release'; Platform = 'x64'; PlatformToolset = 'v143'
                    ImportDirectoryBuildProps = 'false'; ImportDirectoryBuildTargets = 'false'; UserRootDir = '<hermetic-user-root>'
                    VCToolsVersion = '14.40.1'; WindowsTargetPlatformVersion = '10.0.1'
                }
                environment = [ordered]@{ PreferredToolArchitecture = 'x64' }
            }
        }
    }
}

function New-MinimalSealedCandidate {
    param([Parameter(Mandatory = $true)] [string] $Root)
    $candidate = Join-Path $Root 'candidate'; [IO.Directory]::CreateDirectory($candidate) | Out-Null
    $settingsPath = Join-Path $candidate 'ytdlp-interface.json'
    [IO.File]::WriteAllText($settingsPath, '{"outpath":"C:\\old","proxy":"preserve"}', [Text.UTF8Encoding]::new($false))
    $item = Get-Item -LiteralPath $settingsPath
    $manifest = [ordered]@{
        schemaVersion = 1
        createdAtUtc = '2026-08-14T00:00:00.0000000Z'
        attestation = New-FixtureBuildAttestation
        versions = [ordered]@{ product = '2.19.1.0'; ytdlp = '2026.08.13'; ffmpeg = 'fixture'; ffprobe = 'fixture'; deno = 'fixture' }
        files = @([ordered]@{ path = 'ytdlp-interface.json'; sha256 = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash; length = $item.Length })
    }
    $manifestPath = Join-Path $candidate 'candidate-manifest.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ Root = $candidate; SettingsPath = $settingsPath; ManifestPath = $manifestPath; Manifest = $manifest }
}

function Get-TreeInventory {
    param([Parameter(Mandatory = $true)] [string] $Root)
    return @(
        Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName | ForEach-Object {
            $_.FullName.Substring($Root.Length).TrimStart('\', '/') + '|' + $_.Length + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    ) -join "`n"
}

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

function Test-SmokeOutputAcceptsWindowsFfprobeLineEndings {
    $root = New-FixtureRoot
    try {
        $output = Join-Path $root 'output'; [IO.Directory]::CreateDirectory($output) | Out-Null
        $mp3 = Join-Path $output 'result.mp3'; [IO.File]::WriteAllText($mp3, 'fixture', [Text.Encoding]::ASCII)
        $result = Test-SmokeOutput -OutputDirectory $output -FfprobeAction { param($path) "codec_name=mp3`r`nduration=2.0`r`n" }
        Assert-True $result.Valid 'Windows CRLF FFprobe output must prove an MP3 result.'
        Assert-Equal 'ok' $result.ReasonCode 'Windows CRLF FFprobe output must retain the success reason code.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-FailureEvidenceAndSuccessCleanup {
    $root = New-FixtureRoot
    try {
        $evidence = Join-Path $root 'evidence'; [IO.Directory]::CreateDirectory($evidence) | Out-Null
        $failureWorkspace = Join-Path $root 'failed'; [IO.Directory]::CreateDirectory($failureWorkspace) | Out-Null
        Complete-SmokeWorkspace -Workspace $failureWorkspace -EvidenceDirectory $evidence -Succeeded:$false -ReasonCode 'fixture_failure' -RunId 'failed-run' -Mode 'operator-guided'
        Assert-True (Test-Path -LiteralPath $failureWorkspace) 'Failed smoke workspace must be retained.'
        Assert-True (Test-Path -LiteralPath (Join-Path $evidence 'runs\failed-run.json')) 'Failed smoke must retain a run-unique manifest.'
        $successWorkspace = Join-Path $root 'success'; [IO.Directory]::CreateDirectory($successWorkspace) | Out-Null
        $successEvidence = [ordered]@{ relativePath = 'output\fixture.mp3'; sha256 = ('A' * 64); length = 1; duration = 1.0; settingsSha256 = ('C' * 64); ffprobeSha256 = ('D' * 64); noPartFiles = $true }
        Complete-SmokeWorkspace -Workspace $successWorkspace -EvidenceDirectory $evidence -Succeeded:$true -ReasonCode 'ok' -RunId 'successful-run' -Mode 'artifact-only' -CandidateManifestSha256 ('B' * 64) -OutputEvidence $successEvidence
        Assert-False (Test-Path -LiteralPath $successWorkspace) 'Successful smoke workspace must be cleaned up.'
        Assert-True (Test-Path -LiteralPath (Join-Path $evidence 'runs\successful-run.json')) 'Successful smoke must retain a run-unique manifest.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-CleanupTimeoutStillWritesSanitizedFailureEvidence {
    $root = New-FixtureRoot
    try {
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $evidence = Join-Path $root 'evidence'
        try { Complete-SmokeRun -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$true -ReasonCode 'ok' -RunId 'cleanup-timeout' -Mode 'operator-guided' -CleanupAction { throw 'process_cleanup_timeout' }; $threw = $false }
        catch { $threw = $_.Exception.Message -eq 'process_cleanup_timeout' }
        Assert-True $threw 'A cleanup timeout must fail the smoke after recording evidence.'
        $manifestPath = Join-Path $evidence 'runs\cleanup-timeout.json'
        Assert-True (Test-Path -LiteralPath $manifestPath) 'Cleanup timeout must retain a run-unique manifest.'
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            Assert-Equal 'process_cleanup_timeout' $manifest.reasonCode 'Cleanup timeout evidence must use the stable reason code.'
            Assert-False ($manifest.PSObject.Properties.Name -contains 'reason') 'Cleanup timeout evidence must not expose exception text.'
        }
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
        Complete-SmokeWorkspace -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$false -ReasonCode 'gui_start_failed' -RunId 'sanitized-failure' -Mode 'operator-guided'
        $manifestPath = Join-Path $evidence 'runs\sanitized-failure.json'
        Assert-True (Test-Path -LiteralPath $manifestPath) 'Failure evidence must use a run-unique manifest.'
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            Assert-Equal 'gui_start_failed' $manifest.reasonCode 'Evidence must retain only the stable reason code.'
            Assert-Equal 'workspace' $manifest.workspaceId 'Evidence must contain the relative workspace identifier only.'
            Assert-False ($manifest.PSObject.Properties.Name -contains 'reason') 'Evidence must not expose exception text.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeManifestsAreAppendOnlyAndBindArtifactEvidence {
    $root = New-FixtureRoot
    try {
        $evidence = Join-Path $root 'evidence'
        $firstWorkspace = Join-Path $root 'first'; [IO.Directory]::CreateDirectory($firstWorkspace) | Out-Null
        $secondWorkspace = Join-Path $root 'second'; [IO.Directory]::CreateDirectory($secondWorkspace) | Out-Null
        $output = [ordered]@{ relativePath = 'output\fixture.mp3'; sha256 = ('A' * 64); length = 42; duration = 2.0; settingsSha256 = ('C' * 64); ffprobeSha256 = ('D' * 64); noPartFiles = $true }
        Complete-SmokeWorkspace -Workspace $firstWorkspace -EvidenceDirectory $evidence -Succeeded:$false -ReasonCode 'operator_not_confirmed' -RunId 'first-run' -Mode 'operator-guided'
        Complete-SmokeWorkspace -Workspace $secondWorkspace -EvidenceDirectory $evidence -Succeeded:$true -ReasonCode 'ok' -RunId 'second-run' -Mode 'artifact-only' -OutputEvidence $output -CandidateManifestSha256 ('B' * 64)

        $runs = Join-Path $evidence 'runs'
        Assert-True (Test-Path -LiteralPath $runs) 'Smoke evidence must create the runs directory.'
        if (Test-Path -LiteralPath $runs) {
            $manifests = @(Get-ChildItem -LiteralPath $runs -Filter '*.json')
            $successPath = Join-Path $runs 'second-run.json'
            Assert-Equal 2 $manifests.Count 'Separate smoke runs must not overwrite each other evidence.'
            Assert-True (Test-Path -LiteralPath $successPath) 'A successful run must have its own manifest.'
            if (Test-Path -LiteralPath $successPath) {
                $success = Get-Content -LiteralPath $successPath -Raw | ConvertFrom-Json
                Assert-Equal 'artifact-only' $success.mode 'Automation evidence must be classified as artifact-only.'
                Assert-Equal ('B' * 64) $success.candidateManifestSha256 'The success manifest must bind the candidate manifest hash.'
                Assert-Equal ('A' * 64) $success.output.sha256 'The success manifest must bind the MP3 hash.'
                Assert-Equal 42 $success.output.length 'The success manifest must bind the MP3 length.'
                Assert-Equal 2 $success.output.duration 'The success manifest must bind the probed MP3 duration.'
            }
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeOutputRootIsWrittenIntoCandidateSettings {
    $root = New-FixtureRoot
    try {
        $candidate = Join-Path $root 'candidate'; [IO.Directory]::CreateDirectory($candidate) | Out-Null
        $settingsPath = Join-Path $candidate 'ytdlp-interface.json'
        $output = Join-Path $root 'Downloads\ytdlp-interface-smoke-fixture\output'
        [IO.File]::WriteAllText($settingsPath, '{"outpath":"C:\\old","proxy":"preserve"}', [Text.UTF8Encoding]::new($false))
        $command = Get-Command -Name Set-SmokeCandidateOutputPath -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Smoke must provide a candidate settings output-path writer.'
        if ($null -ne $command) {
            Set-SmokeCandidateOutputPath -CandidateRoot $candidate -OutputDirectory $output
            $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
            Assert-Equal $output $settings.outpath 'The candidate GUI settings must use the unique smoke output root.'
            Assert-Equal 'preserve' $settings.proxy 'The smoke output-path writer must preserve unrelated candidate settings.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeExecutionCopyPreservesSealedCandidate {
    $root = New-FixtureRoot
    try {
        $candidate = Join-Path $root 'candidate'; [IO.Directory]::CreateDirectory($candidate) | Out-Null
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $settingsPath = Join-Path $candidate 'ytdlp-interface.json'
        [IO.File]::WriteAllText($settingsPath, '{"outpath":"C:\\old","proxy":"preserve"}', [Text.UTF8Encoding]::new($false))
        $file = Get-Item -LiteralPath $settingsPath
        $manifest = [ordered]@{ schemaVersion = 1; createdAtUtc = '2026-08-14T00:00:00.0000000Z'; attestation = New-FixtureBuildAttestation; versions = [ordered]@{ product = '2.19.1.0'; ytdlp = '2026.08.13'; ffmpeg = 'fixture'; ffprobe = 'fixture'; deno = 'fixture' }; files = @([ordered]@{ path = 'ytdlp-interface.json'; sha256 = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash; length = $file.Length }) }
        $manifestPath = Join-Path $candidate 'candidate-manifest.json'
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        $sealedHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
        $command = Get-Command -Name Copy-SealedCandidateForSmoke -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Smoke must provide a sealed candidate execution-copy constructor.'
        if ($null -ne $command) {
            $execution = Copy-SealedCandidateForSmoke -CandidateRoot $candidate -Workspace $workspace
            Set-SmokeCandidateOutputPath -CandidateRoot $execution -OutputDirectory (Join-Path $workspace 'output')
            Assert-Equal $sealedHash (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash 'Smoke must not change the sealed candidate manifest.'
            Assert-Equal 'C:\old' (Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json).outpath 'Smoke must not change the sealed candidate settings.'
            Assert-Equal (Join-Path $workspace 'output') (Get-Content -LiteralPath (Join-Path $execution 'ytdlp-interface.json') -Raw | ConvertFrom-Json).outpath 'Only the execution copy may receive the smoke output path.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeWorkspaceUsesDownloadsContainedRunRoot {
    $root = New-FixtureRoot
    try {
        $downloads = Join-Path $root 'Downloads'; [IO.Directory]::CreateDirectory($downloads) | Out-Null
        $command = Get-Command -Name New-SmokeWorkspace -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Smoke must provide a Downloads-contained workspace constructor.'
        if ($null -ne $command) {
            $workspace = New-SmokeWorkspace -DownloadsPath $downloads -RunId 'fixture-run'
            Assert-True (Test-PathContained -Root $downloads -Path $workspace.Root) 'The smoke root must be contained by Downloads.'
            Assert-True (Test-PathContained -Root $workspace.Root -Path $workspace.OutputDirectory) 'The output path must be contained by its smoke root.'
            Assert-Equal 'ytdlp-interface-smoke-fixture-run' (Split-Path -Leaf $workspace.Root) 'The smoke root name must bind the run ID.'
        }
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

function Test-ExistingDependencyRootsCannotBypassArchiveRequirement {
    $root = New-FixtureRoot
    try {
        $missingArchiveDirectory = Join-Path $root 'missing-archive'
        try { Initialize-OfficialDependencies -SourceRoot $repositoryRoot -DependencyArchiveDirectory $missingArchiveDirectory; $threw = $false } catch { $threw = $true }
        Assert-True $threw 'Existing dependency roots must not bypass the reviewed archive requirement.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-IsolatedBuildSourceExcludesExistingDependencyRoots {
    $root = New-FixtureRoot
    try {
        $source = Join-Path $root 'source'; $workspace = Join-Path $root 'workspace'
        [IO.Directory]::CreateDirectory($source) | Out-Null
        [IO.File]::WriteAllText((Join-Path $source 'tracked.txt'), 'trusted-source', [Text.Encoding]::ASCII)
        foreach ($name in @('bit7z', 'nana', 'libpng', 'libjpeg-turbo-3.1.2', '.git')) {
            $path = Join-Path $source $name; [IO.Directory]::CreateDirectory($path) | Out-Null
            [IO.File]::WriteAllText((Join-Path $path 'untrusted.txt'), 'must-not-copy', [Text.Encoding]::ASCII)
        }
        $command = Get-Command -Name New-IsolatedBuildSource -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Candidate build must construct an isolated source tree before dependency extraction.'
        if ($null -ne $command) {
            $isolated = New-IsolatedBuildSource -SourceRoot $source -WorkspaceRoot $workspace -DependencyRoots @('bit7z', 'nana', 'libpng', 'libjpeg-turbo-3.1.2') -TrackedPaths @('tracked.txt')
            Assert-True (Test-Path -LiteralPath (Join-Path $isolated 'tracked.txt')) 'The isolated source tree must retain tracked source inputs.'
            foreach ($name in @('bit7z', 'nana', 'libpng', 'libjpeg-turbo-3.1.2', '.git')) { Assert-False (Test-Path -LiteralPath (Join-Path $isolated $name)) "The isolated source tree must exclude pre-existing $name." }
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-IsolatedBuildWorkspaceUsesConfiguredShortBase {
    $root = New-FixtureRoot
    try {
        $base = Join-Path $root 'b'
        $command = Get-Command -Name New-IsolatedBuildWorkspace -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Candidate build must create its isolated workspace through a dedicated bounded-path helper.'
        if ($null -ne $command) {
            $workspace = New-IsolatedBuildWorkspace -WorkspaceBase $base
            Assert-True (Test-PathContained -Root $base -Path $workspace) 'The isolated workspace must remain contained by its configured base.'
            Assert-True ((Split-Path -Leaf $workspace).StartsWith('b-', [StringComparison]::Ordinal)) 'The isolated workspace leaf must use the compact build prefix.'
            Assert-True (([IO.Path]::GetFullPath($workspace)).Length - ([IO.Path]::GetFullPath($base)).Length -lt 36) 'The isolated workspace leaf must remain compact enough for native build intermediates.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-ParentProvenanceRequiresRollbackIdentity {
    $command = Get-Command -Name Assert-ParentProvenanceShape -ErrorAction SilentlyContinue
    Assert-True ($null -ne $command) 'Candidate build must validate parent provenance rollback identity.'
    if ($null -ne $command) {
        $legacy = [pscustomobject]@{ repository = 'yt-dlp/yt-dlp-nightly-builds'; channel = 'nightly'; tag = '2026.08.04'; sha256 = ('A' * 64); backupPath = 'C:\fixture\yt-dlp.exe.backup' }
        try { Assert-ParentProvenanceShape -Provenance $legacy; $threw = $false } catch { $threw = $_.Exception.Message -eq 'Parent runtime provenance rollback identity is missing.' }
        Assert-True $threw 'Legacy provenance without prior version and hash must be rejected.'
    }
}

function Test-BackupVersionVerificationRunsNonExeBackupFromTemporaryExecutable {
    $root = New-FixtureRoot
    try {
        $backup = Join-Path $root 'yt-dlp.exe.backup-fixture'
        [IO.File]::WriteAllText($backup, 'previous-binary', [Text.Encoding]::ASCII)
        $command = Get-Command -Name Get-BackupYtDlpVersion -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Candidate build must verify a non-.exe backup version through a temporary executable copy.'
        if ($null -ne $command) {
            $version = Get-BackupYtDlpVersion -BackupPath $backup -VersionReader { param($path) [IO.File]::ReadAllText($path, [Text.Encoding]::ASCII) }
            Assert-Equal 'previous-binary' $version 'Backup version verification must read the temporary executable copy.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SourceAttestationBindsGitRevisionAndWorktreeState {
    $root = New-FixtureRoot
    try {
        $command = Get-Command -Name Get-SourceAttestation -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Candidate build must provide source attestation.'
        $git = Join-Path $root 'git.cmd'
        [IO.File]::WriteAllText((Join-Path $root 'tracked.txt'), 'tracked', [Text.Encoding]::ASCII)
        $fakeGit = "@echo off`r`necho %* | findstr /c:`"rev-parse`" >nul`r`nif not errorlevel 1 (echo 0123456789012345678901234567890123456789& exit /b 0)`r`necho %* | findstr /c:`"status`" >nul`r`nif not errorlevel 1 exit /b 0`r`necho tracked.txt`r`n"
        [IO.File]::WriteAllText($git, $fakeGit, [Text.Encoding]::ASCII)
        if ($null -ne $command) {
            $attestation = Get-SourceAttestation -SourceRoot $root -GitPath $git
            Assert-Equal '0123456789012345678901234567890123456789' $attestation.commit 'Source attestation must retain the verified Git commit.'
            Assert-True (-not [string]::IsNullOrWhiteSpace($attestation.commit)) 'Source attestation must record a verified Git commit.'
            Assert-True $attestation.Contains('dirty') 'Source attestation must classify whether the worktree is dirty.'
            Assert-False ([bool]$attestation.dirty) 'A clean source attestation must record dirty=false.'
            Assert-True ([string]$attestation.treeSha256 -match '^[A-F0-9]{64}$') 'Source attestation must bind exact tracked input bytes.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-DependencyLibraryAttestationBindsLinkerInputs {
    $root = New-FixtureRoot
    try {
        $library = Join-Path $root 'bit7z64.lib'
        [IO.File]::WriteAllText($library, 'fixture-library', [Text.Encoding]::ASCII)
        $command = Get-Command -Name Get-DependencyLibraryAttestation -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Candidate build must provide dependency library attestation.'
        if ($null -ne $command) {
            $attestation = @(Get-DependencyLibraryAttestation -Plan @([pscustomobject]@{ Name = 'bit7z'; LibraryPath = $library }))
            Assert-Equal 1 $attestation.Count 'Each linker input must produce one attestation entry.'
            Assert-Equal 'bit7z64.lib' $attestation[0].library 'The attestation must retain the actual linker input name.'
            Assert-Equal (Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash $attestation[0].sha256 'The attestation must retain the actual linker input hash.'
            Assert-Equal 15 $attestation[0].length 'The attestation must retain the actual linker input length.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-BuildCommandAttestationIncludesDependenciesWithoutAbsoluteSourcePaths {
    $root = New-FixtureRoot
    try {
        $command = Get-Command -Name Get-BuildCommandAttestation -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Candidate build must attest every dependency and product build command.'
        if ($null -ne $command) {
            $plan = @(
                [pscustomobject]@{ Name = 'bit7z'; FilePath = 'C:\tools\MSBuild.exe'; Arguments = @((Join-Path $root 'bit7z\bit7z.sln')); BuildArguments = @() },
                [pscustomobject]@{ Name = 'libjpeg-turbo'; FilePath = 'C:\tools\cmake.exe'; Arguments = @('-S', (Join-Path $root 'libjpeg-turbo')); BuildArguments = @('--build', (Join-Path $root 'out')) }
            )
            $entries = @(Get-BuildCommandAttestation -SourceRoot $root -DependencyPlan $plan -ProductExecutable 'C:\tools\MSBuild.exe' -ProductArguments @((Join-Path $root 'product.sln')))
            Assert-Equal 4 $entries.Count 'Each configure/build dependency command plus product build must be attested.'
            Assert-True ($entries.name -contains 'bit7z Release x64 build') 'Dependency command inventory must identify bit7z.'
            Assert-True ($entries.name -contains 'libjpeg-turbo Release x64 build') 'Dependency build phase must be retained separately.'
            Assert-True ($entries.name -contains 'Release x64 MSBuild') 'Product build command must remain attested.'
            Assert-False (($entries | ConvertTo-Json -Depth 5) -match [regex]::Escape($root)) 'Build command attestation must normalize source-root paths.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
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

function Test-ProcessEnvironmentNormalizesDuplicatePathKeys {
    $command = Get-Command -Name Normalize-ProcessEnvironmentPath -ErrorAction SilentlyContinue
    Assert-True ($null -ne $command) 'Build process launcher must normalize duplicate Path/PATH environment keys.'
    if ($null -ne $command) {
        $environment = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
        $environment.Add('Path', 'canonical-path')
        $environment.Add('PATH', 'duplicate-path')
        Normalize-ProcessEnvironmentPath -Environment $environment
        Assert-Equal 1 @($environment.Keys | Where-Object { $_ -ceq 'Path' -or $_ -ceq 'PATH' }).Count 'The child environment must contain exactly one case-insensitive Path key.'
        Assert-Equal 'canonical-path' $environment['Path'] 'The canonical Path value must be retained.'
    }
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

function Test-SmokeRejectsCallerExpectedManifestDigestMismatch {
    $root = New-FixtureRoot
    try {
        $fixture = New-MinimalSealedCandidate -Root $root
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        try {
            Copy-SealedCandidateForSmoke -CandidateRoot $fixture.Root -Workspace $workspace -ExpectedCandidateManifestSha256 ('F' * 64) | Out-Null
            $actual = 'no_failure'
        }
        catch { $actual = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_digest_mismatch' $actual 'A caller-supplied expected candidate-manifest digest mismatch must be rejected before copying files.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeRejectsDuplicatePathsAndMalformedManifestMetadata {
    $root = New-FixtureRoot
    try {
        foreach ($case in @('duplicate_path', 'malformed_hash', 'invalid_length')) {
            $caseRoot = Join-Path $root $case; [IO.Directory]::CreateDirectory($caseRoot) | Out-Null
            $fixture = New-MinimalSealedCandidate -Root $caseRoot
            $entry = $fixture.Manifest.files[0]
            switch ($case) {
                'duplicate_path' { $fixture.Manifest.files = @($entry, $entry) }
                'malformed_hash' { $entry.sha256 = 'not-a-sha256' }
                'invalid_length' { $entry.length = -1 }
            }
            [IO.File]::WriteAllText($fixture.ManifestPath, ($fixture.Manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
            $workspace = Join-Path $caseRoot 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
            try { Copy-SealedCandidateForSmoke -CandidateRoot $fixture.Root -Workspace $workspace | Out-Null; $actual = 'no_failure' }
            catch { $actual = $_.Exception.Message }
            Assert-Equal 'candidate_manifest_invalid' $actual "Manifest case $case must fail structural validation before file comparison."
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeSettingsOverrideProducesExplicitDerivativeAttestation {
    $root = New-FixtureRoot
    try {
        $fixture = New-MinimalSealedCandidate -Root $root
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $execution = Copy-SealedCandidateForSmoke -CandidateRoot $fixture.Root -Workspace $workspace
        Set-SmokeCandidateOutputPath -CandidateRoot $execution -OutputDirectory (Join-Path $workspace 'output')
        $secondWorkspace = Join-Path $root 'second-workspace'; [IO.Directory]::CreateDirectory($secondWorkspace) | Out-Null
        try { Copy-SealedCandidateForSmoke -CandidateRoot $execution -Workspace $secondWorkspace | Out-Null; $revalidation = 'no_failure' }
        catch { $revalidation = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_mismatch' $revalidation 'The mutated execution settings must not remain falsely described by the sealed base manifest.'

        $command = Get-Command -Name Get-SmokeExecutionAttestation -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Smoke must create an explicit derivative settings-overlay attestation.'
        if ($null -ne $command) {
            $baseHash = (Get-FileHash -LiteralPath $fixture.ManifestPath -Algorithm SHA256).Hash
            $settingsHash = (Get-FileHash -LiteralPath (Join-Path $execution 'ytdlp-interface.json') -Algorithm SHA256).Hash
            $attestation = Get-SmokeExecutionAttestation -ExecutionCandidate $execution -BaseCandidateManifestSha256 $baseHash
            Assert-Equal $baseHash $attestation.baseCandidateManifestSha256 'The derivative attestation must bind the sealed base manifest.'
            Assert-Equal $settingsHash $attestation.settingsSha256 'The derivative attestation must bind the settings file actually executed.'
            Assert-Equal 'settings-overlay' $attestation.kind 'The execution candidate must be classified as a settings overlay, not as the sealed base tree.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeExecutionOverlayRejectsBaseMismatchAndNonSettingsMutation {
    $root = New-FixtureRoot
    try {
        $command = Get-Command -Name Assert-SmokeExecutionOverlay -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Smoke must expose a strict execution-overlay validator.'
        if ($null -eq $command) { return }
        $fixture = New-MinimalSealedCandidate -Root $root
        $payloadPath = Join-Path $fixture.Root 'ffmpeg.exe'
        [IO.File]::WriteAllText($payloadPath, 'fixture-ffmpeg', [Text.Encoding]::ASCII)
        $payload = Get-Item -LiteralPath $payloadPath
        $fixture.Manifest.files += [ordered]@{ path = 'ffmpeg.exe'; sha256 = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash; length = $payload.Length }
        [IO.File]::WriteAllText($fixture.ManifestPath, ($fixture.Manifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $output = Join-Path $workspace 'output'; [IO.Directory]::CreateDirectory($output) | Out-Null
        $execution = Copy-SealedCandidateForSmoke -CandidateRoot $fixture.Root -Workspace $workspace
        Set-SmokeCandidateOutputPath -CandidateRoot $execution -OutputDirectory $output
        $baseHash = (Get-FileHash -LiteralPath $fixture.ManifestPath -Algorithm SHA256).Hash
        try { Assert-SmokeExecutionOverlay -ExecutionCandidate $execution -BaseCandidateRoot $fixture.Root -BaseCandidateManifestSha256 ('F' * 64) -ExpectedOutputDirectory $output -Phase 'pre-run'; $baseResult = 'no_failure' }
        catch { $baseResult = $_.Exception.Message }
        Assert-Equal 'candidate_execution_base_manifest_mismatch' $baseResult 'Overlay validation must reject a wrong base manifest binding.'
        $attestation = Assert-SmokeExecutionOverlay -ExecutionCandidate $execution -BaseCandidateRoot $fixture.Root -BaseCandidateManifestSha256 $baseHash -ExpectedOutputDirectory $output -Phase 'pre-run'
        Assert-Equal 'settings-overlay' $attestation.kind 'A valid execution copy must be explicitly classified as a settings overlay.'
        Assert-True ([bool]$attestation.payloadsUnchanged) 'A pre-run overlay attestation must prove non-settings payloads are unchanged.'
        [IO.File]::WriteAllText((Join-Path $execution 'ffmpeg.exe'), 'mutated-after-copy', [Text.Encoding]::ASCII)
        try { Assert-SmokeExecutionOverlay -ExecutionCandidate $execution -BaseCandidateRoot $fixture.Root -BaseCandidateManifestSha256 $baseHash -ExpectedOutputDirectory $output -Phase 'post-run'; $payloadResult = 'no_failure' }
        catch { $payloadResult = $_.Exception.Message }
        Assert-Equal 'candidate_execution_payload_changed' $payloadResult 'A post-run mutation of a non-settings payload must invalidate the execution copy.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeExecutionOverlayAllowsOnlyOutpathSettingsChange {
    $root = New-FixtureRoot
    try {
        $command = Get-Command -Name Assert-SmokeExecutionOverlay -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Smoke must expose a strict settings-overlay validator.'
        if ($null -eq $command) { return }
        $fixture = New-MinimalSealedCandidate -Root $root
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $output = Join-Path $workspace 'output'; [IO.Directory]::CreateDirectory($output) | Out-Null
        $execution = Copy-SealedCandidateForSmoke -CandidateRoot $fixture.Root -Workspace $workspace
        Set-SmokeCandidateOutputPath -CandidateRoot $execution -OutputDirectory $output
        $baseHash = (Get-FileHash -LiteralPath $fixture.ManifestPath -Algorithm SHA256).Hash
        $settingsPath = Join-Path $execution 'ytdlp-interface.json'
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $settings.proxy = 'mutated-proxy'
        [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        try { Assert-SmokeExecutionOverlay -ExecutionCandidate $execution -BaseCandidateRoot $fixture.Root -BaseCandidateManifestSha256 $baseHash -ExpectedOutputDirectory $output -Phase 'post-run'; $actual = 'no_failure' }
        catch { $actual = $_.Exception.Message }
        Assert-Equal 'settings_overlay_invalid' $actual 'The explicit overlay validator must reject settings changes outside the outpath override.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeExecutionOverlayRejectsBaseRootOverlap {
    $root = New-FixtureRoot
    try {
        $command = Get-Command -Name Assert-SmokeExecutionOverlay -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Smoke must reject an execution overlay rooted at the sealed candidate.'
        if ($null -eq $command) { return }
        $fixture = New-MinimalSealedCandidate -Root $root
        $baseHash = (Get-FileHash -LiteralPath $fixture.ManifestPath -Algorithm SHA256).Hash
        try { Assert-SmokeExecutionOverlay -ExecutionCandidate $fixture.Root -BaseCandidateRoot $fixture.Root -BaseCandidateManifestSha256 $baseHash -ExpectedOutputDirectory 'C:\old' -Phase 'pre-run'; $actual = 'no_failure' }
        catch { $actual = $_.Exception.Message }
        Assert-Equal 'candidate_execution_base_overlap' $actual 'The execution overlay must never target the sealed candidate root.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeEvidenceLivesOutsideCandidateAndPreservesWholeTree {
    $root = New-FixtureRoot
    try {
        $fixture = New-MinimalSealedCandidate -Root $root
        $downloads = Join-Path $root 'Downloads'; [IO.Directory]::CreateDirectory($downloads) | Out-Null
        $workspace = Join-Path $downloads 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $before = Get-TreeInventory -Root $fixture.Root
        $command = Get-Command -Name Get-SmokeEvidenceDirectory -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Smoke must resolve persistent evidence outside the sealed CandidateRoot.'
        if ($null -ne $command) {
            $evidence = Get-SmokeEvidenceDirectory -DownloadsPath $downloads -CandidateRoot $fixture.Root
            Assert-False (Test-PathOverlap -First $fixture.Root -Second $evidence) 'Persistent evidence must not overlap the sealed candidate tree.'
            Complete-SmokeWorkspace -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$false -ReasonCode 'fixture_failure' -RunId 'external-evidence' -Mode 'operator-guided'
            Assert-Equal $before (Get-TreeInventory -Root $fixture.Root) 'Writing smoke evidence must leave the complete candidate tree inventory unchanged.'
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-CleanupFailureOnFailedRunIsRecordedAndThrown {
    $root = New-FixtureRoot
    try {
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $evidence = Join-Path $root 'evidence'
        try {
            Complete-SmokeRun -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$false -ReasonCode 'automation_required' -RunId 'failed-cleanup' -Mode 'operator-guided' -CleanupAction { throw 'process_cleanup_timeout' }
            $actual = 'no_failure'
        }
        catch { $actual = $_.Exception.Message }
        Assert-Equal 'process_cleanup_timeout' $actual 'Cleanup failure must remain observable even when the smoke had already failed.'
        $manifest = Get-Content -LiteralPath (Join-Path $evidence 'runs\failed-cleanup.json') -Raw | ConvertFrom-Json
        Assert-Equal 'process_cleanup_timeout' $manifest.reasonCode 'Cleanup failure must be the terminal run reason code.'
        Assert-True ($manifest.PSObject.Properties.Name -contains 'cleanupSucceeded') 'Run evidence must record cleanup outcome explicitly.'
        if ($manifest.PSObject.Properties.Name -contains 'cleanupSucceeded') { Assert-False ([bool]$manifest.cleanupSucceeded) 'A cleanup timeout must record cleanupSucceeded=false.' }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeSuccessEvidenceSeparatesProofClaims {
    $root = New-FixtureRoot
    try {
        $command = Get-Command -Name Complete-SmokeWorkspace -ErrorAction Stop
        Assert-True ($command.Parameters.ContainsKey('ProofEvidence')) 'Successful smoke evidence must accept explicit, separate proof claims.'
        if (-not $command.Parameters.ContainsKey('ProofEvidence')) { return }
        $output = [ordered]@{ relativePath = 'output\fixture.mp3'; sha256 = ('A' * 64); length = 42; duration = 2.0; settingsSha256 = ('C' * 64); ffprobeSha256 = ('D' * 64); noPartFiles = $true }
        $proof = [ordered]@{ artifactValidated = $true; guiInteractionProven = $false; operatorAttested = $false }
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $evidence = Join-Path $root 'evidence'
        Complete-SmokeWorkspace -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$true -ReasonCode 'ok' -RunId 'artifact-only-proof' -Mode 'artifact-only' -CandidateManifestSha256 ('B' * 64) -OutputEvidence $output -ProofEvidence $proof
        $manifest = Get-Content -LiteralPath (Join-Path $evidence 'runs\artifact-only-proof.json') -Raw | ConvertFrom-Json
        Assert-True ([bool]$manifest.proof.artifactValidated) 'Artifact-only success must record artifact validation.'
        Assert-False ([bool]$manifest.proof.guiInteractionProven) 'Artifact-only success must not claim GUI interaction proof.'
        Assert-False ([bool]$manifest.proof.operatorAttested) 'Artifact-only success must not claim an operator attestation.'

        $invalidWorkspace = Join-Path $root 'invalid-workspace'; [IO.Directory]::CreateDirectory($invalidWorkspace) | Out-Null
        $invalidProof = [ordered]@{ artifactValidated = $true; guiInteractionProven = $true; operatorAttested = $false }
        try { Complete-SmokeWorkspace -Workspace $invalidWorkspace -EvidenceDirectory $evidence -Succeeded:$true -ReasonCode 'ok' -RunId 'false-gui-proof' -Mode 'artifact-only' -CandidateManifestSha256 ('B' * 64) -OutputEvidence $output -ProofEvidence $invalidProof; $actual = 'no_failure' }
        catch { $actual = $_.Exception.Message }
        Assert-Equal 'smoke_success_evidence_invalid' $actual 'Artifact-only mode must reject a claim that GUI interaction was proven.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeBindsDetailedArtifactEvidenceBeforeDeletingWorkspace {
    $root = New-FixtureRoot
    try {
        $workspace = Join-Path $root 'workspace'; $output = Join-Path $workspace 'output'
        [IO.Directory]::CreateDirectory($output) | Out-Null
        $mp3 = Join-Path $output 'fixture.mp3'; [IO.File]::WriteAllText($mp3, 'fixture-mp3', [Text.Encoding]::ASCII)
        $mp3Hash = (Get-FileHash -LiteralPath $mp3 -Algorithm SHA256).Hash
        $settings = Join-Path $workspace 'ytdlp-interface.json'; [IO.File]::WriteAllText($settings, '{"outpath":"output"}', [Text.UTF8Encoding]::new($false))
        $probe = "codec_name=mp3`r`nduration=2.0`r`n"
        $command = Get-Command -Name New-SmokeSuccessEvidence -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Smoke must bind MP3, settings, FFprobe, and no-part evidence while the workspace still exists.'
        if ($null -eq $command) { return }
        $evidence = Join-Path $root 'evidence'
        $bound = New-SmokeSuccessEvidence -Workspace $workspace -OutputDirectory $output -Mp3Path $mp3 -SettingsPath $settings -FfprobeOutput $probe -EvidenceDirectory $evidence -RunId 'bound-before-delete'
        $arguments = @{
            Workspace = $workspace; EvidenceDirectory = $evidence; Succeeded = $true; ReasonCode = 'ok'; RunId = 'bound-before-delete'; Mode = 'artifact-only'
            CandidateManifestSha256 = ('B' * 64); OutputEvidence = $bound
        }
        $complete = Get-Command -Name Complete-SmokeWorkspace -ErrorAction Stop
        if ($complete.Parameters.ContainsKey('ProofEvidence')) { $arguments.ProofEvidence = [ordered]@{ artifactValidated = $true; guiInteractionProven = $false; operatorAttested = $false } }
        Complete-SmokeWorkspace @arguments
        Assert-False (Test-Path -LiteralPath $workspace) 'Successful smoke must delete its temporary workspace only after evidence is persisted.'
        $manifest = Get-Content -LiteralPath (Join-Path $evidence 'runs\bound-before-delete.json') -Raw | ConvertFrom-Json
        Assert-Equal $mp3Hash $manifest.output.sha256 'Persisted evidence must bind the deleted MP3 bytes.'
        Assert-True ([string]$manifest.output.settingsSha256 -match '^[A-Fa-f0-9]{64}$') 'Persisted evidence must bind the settings file used by the GUI.'
        Assert-True ([string]$manifest.output.ffprobeSha256 -match '^[A-Fa-f0-9]{64}$') 'Persisted evidence must bind the exact FFprobe output.'
        Assert-True ([bool]$manifest.output.noPartFiles) 'Persisted evidence must attest that no .part file was present.'
        Assert-Equal 'fixture-mp3' ([IO.File]::ReadAllText((Join-Path $evidence ([string]$manifest.output.retainedMp3)), [Text.Encoding]::ASCII)) 'The exact MP3 body must remain available after workspace deletion.'
        Assert-Equal '{"outpath":"output"}' ([IO.File]::ReadAllText((Join-Path $evidence ([string]$manifest.output.retainedSettings)), [Text.Encoding]::UTF8)) 'The exact executed settings body must remain available after workspace deletion.'
        Assert-Equal $probe ([IO.File]::ReadAllText((Join-Path $evidence ([string]$manifest.output.retainedFfprobe)), [Text.Encoding]::UTF8)) 'The raw FFprobe body must remain available after workspace deletion.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeCapturesSuccessEvidenceAfterCleanup {
    $root = New-FixtureRoot
    try {
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        $mp3 = Join-Path $workspace 'fixture.mp3'; [IO.File]::WriteAllText($mp3, 'before-cleanup', [Text.Encoding]::ASCII)
        $evidence = Join-Path $root 'evidence'
        $proof = [ordered]@{ artifactValidated = $true; guiInteractionProven = $false; operatorAttested = $false }
        Complete-SmokeRun -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$true -ReasonCode 'ok' -RunId 'post-cleanup-capture' -Mode 'artifact-only' -CandidateManifestSha256 ('B' * 64) -ProofEvidence $proof -CleanupAction {
            [IO.File]::WriteAllText($mp3, 'after-cleanup', [Text.Encoding]::ASCII)
        } -SuccessEvidenceAction {
            [ordered]@{ relativePath = 'fixture.mp3'; sha256 = (Get-FileHash -LiteralPath $mp3 -Algorithm SHA256).Hash; length = (Get-Item $mp3).Length; duration = 1.0; settingsSha256 = ('C' * 64); ffprobeSha256 = ('D' * 64); noPartFiles = $true }
        }
        $manifest = Get-Content -LiteralPath (Join-Path $evidence 'runs\post-cleanup-capture.json') -Raw | ConvertFrom-Json
        $expectedPath = Join-Path $root 'expected.mp3'; [IO.File]::WriteAllText($expectedPath, 'after-cleanup', [Text.Encoding]::ASCII)
        Assert-Equal (Get-FileHash -LiteralPath $expectedPath -Algorithm SHA256).Hash $manifest.output.sha256 'Successful evidence must be produced after process cleanup has quiesced the workspace.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-BuildSourceMaterializesTrackedFilesOnly {
    $root = New-FixtureRoot
    try {
        $source = Join-Path $root 'source'; $workspace = Join-Path $root 'workspace'
        [IO.Directory]::CreateDirectory($source) | Out-Null
        [IO.File]::WriteAllText((Join-Path $source 'tracked.cpp'), 'tracked-source', [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText((Join-Path $source 'ignored.obj'), 'ignored-build-artifact', [Text.Encoding]::ASCII)
        $command = Get-Command -Name New-IsolatedBuildSource -ErrorAction Stop
        Assert-True ($command.Parameters.ContainsKey('TrackedPaths')) 'Build source materialization must accept the exact Git-tracked path set.'
        if (-not $command.Parameters.ContainsKey('TrackedPaths')) { return }
        $isolated = New-IsolatedBuildSource -SourceRoot $source -WorkspaceRoot $workspace -DependencyRoots @('dependencies') -TrackedPaths @('tracked.cpp')
        Assert-True (Test-Path -LiteralPath (Join-Path $isolated 'tracked.cpp')) 'Tracked source must be materialized.'
        Assert-False (Test-Path -LiteralPath (Join-Path $isolated 'ignored.obj')) 'Ignored build artifacts must not enter the isolated source tree.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SourceInputAttestationRejectsDirtyAndBindsExactTree {
    $root = New-FixtureRoot
    try {
        $source = Join-Path $root 'source'; [IO.Directory]::CreateDirectory($source) | Out-Null
        $tracked = Join-Path $source 'tracked.cpp'; [IO.File]::WriteAllText($tracked, 'version-one', [Text.Encoding]::ASCII)
        $command = Get-Command -Name Get-SourceInputAttestation -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Candidate build must provide an exact tracked-source input attestation.'
        if ($null -eq $command) { return }
        try { Get-SourceInputAttestation -SourceRoot $source -Commit ('1' * 40) -StatusPorcelain ' M tracked.cpp' -TrackedPaths @('tracked.cpp') | Out-Null; $actual = 'no_failure' }
        catch { $actual = $_.Exception.Message }
        Assert-Equal 'source_worktree_dirty' $actual 'Dirty or otherwise unbound source must be rejected before build.'
        $first = Get-SourceInputAttestation -SourceRoot $source -Commit ('1' * 40) -StatusPorcelain '' -TrackedPaths @('tracked.cpp')
        [IO.File]::WriteAllText($tracked, 'version-two', [Text.Encoding]::ASCII)
        $second = Get-SourceInputAttestation -SourceRoot $source -Commit ('1' * 40) -StatusPorcelain '' -TrackedPaths @('tracked.cpp')
        Assert-Equal 1 $first.trackedFileCount 'Source attestation must bind the exact tracked-file count.'
        Assert-True ([string]$first.treeSha256 -match '^[A-F0-9]{64}$') 'Source attestation must contain a SHA-256 tree digest.'
        Assert-False ($first.treeSha256 -eq $second.treeSha256) 'Changing tracked bytes must change the exact input tree digest.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-HermeticBuildContextDisablesExternalPropsAndBindsEffectiveContext {
    $root = New-FixtureRoot
    try {
        $source = Join-Path $root 'source'; $workspace = Join-Path $root 'workspace'
        [IO.Directory]::CreateDirectory($source) | Out-Null
        $command = Get-Command -Name New-HermeticBuildContext -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Candidate build must create a hermetic MSBuild context.'
        if ($null -eq $command) { return }
        $context = New-HermeticBuildContext -SourceRoot $source -WorkspaceRoot $workspace -VCToolsVersion '14.40.1' -WindowsSdkVersion '10.0.1'
        Assert-True (Test-Path -LiteralPath $context.UserRootDirectory -PathType Container) 'Hermetic build must redirect UserRootDir to an empty controlled directory.'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $context.UserRootDirectory -Force).Count 'Controlled UserRootDir must begin empty.'
        Assert-Equal 'false' $context.EffectiveProperties.ImportDirectoryBuildProps 'Directory.Build.props imports must be explicitly disabled.'
        Assert-Equal 'false' $context.EffectiveProperties.ImportDirectoryBuildTargets 'Directory.Build.targets imports must be explicitly disabled.'
        Assert-Equal '<source>' $context.AttestedWorkingDirectory 'Build command attestation must bind its normalized working directory.'
        Assert-Equal 'x64' $context.AttestedEnvironment.PreferredToolArchitecture 'Build command attestation must bind the relevant architecture environment.'
        $plan = Get-ReleaseX64DependencyPlan -SourceRoot $source -CommonMsBuildArguments $context.MsBuildArguments -CmakeVsGlobalsArgument $context.CmakeVsGlobalsArgument
        foreach ($dependency in @($plan | Select-Object -First 3)) {
            Assert-True ($dependency.Arguments -contains '/p:ImportDirectoryBuildProps=false') "$($dependency.Name) MSBuild must disable Directory.Build.props."
            Assert-True (@($dependency.Arguments | Where-Object { $_ -like '/p:UserRootDir=*' }).Count -eq 1) "$($dependency.Name) MSBuild must redirect user props."
        }
        Assert-Equal '/m' $plan[3].BuildArguments[7] 'CMake-generated MSBuild must use the sealed parallel build switch.'
        Assert-Equal '/t:Build' $plan[3].BuildArguments[8] 'CMake-generated MSBuild must use the sealed Build target.'
        Assert-True ($plan[3].BuildArguments -contains '/p:ImportDirectoryBuildProps=false') 'CMake-generated MSBuild must disable Directory.Build.props.'
        Assert-True (@($plan[3].BuildArguments | Where-Object { $_ -like '/p:UserRootDir=*' }).Count -eq 1) 'CMake-generated MSBuild must redirect user props.'
        [IO.File]::WriteAllText((Join-Path $root 'Directory.Build.props'), '<Project><Target Name="Hostile" BeforeTargets="Build"><Error Text="hostile-parent-props-imported" /></Target></Project>', [Text.Encoding]::UTF8)
        $vsGlobals = @($plan[3].Arguments | Where-Object { $_ -like '-DCMAKE_VS_GLOBALS=*' })
        Assert-Equal 1 $vsGlobals.Count 'CMake configure must receive exactly one sealed Visual Studio globals definition despite hostile parent props.'
        if ($vsGlobals.Count -eq 1) {
            foreach ($literal in @('ImportDirectoryBuildProps=false', 'ImportDirectoryBuildTargets=false', 'UserRootDir=', 'VCToolsVersion=14.40.1', 'WindowsTargetPlatformVersion=10.0.1')) {
                Assert-True ($vsGlobals[0] -like ('*' + $literal + '*')) "CMake configure VS globals must bind $literal."
            }
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-ToolchainAttestationIncludesNativeCompilerLinkerResourceCompilerAndSdk {
    $root = New-FixtureRoot
    try {
        $paths = [ordered]@{}
        foreach ($name in @('msbuild', 'cmake', 'cl', 'link', 'rc', 'sdk')) {
            $path = Join-Path $root ($name + '.exe'); [IO.File]::WriteAllText($path, $name, [Text.Encoding]::ASCII); $paths[$name] = $path
        }
        $tools = [pscustomobject]@{
            MsBuildPath = $paths.msbuild; CompilerPath = $paths.cl; LinkerPath = $paths.link; ResourceCompilerPath = $paths.rc
            VCToolsVersion = '14.40.1'; WindowsSdkVersion = '10.0.1'; WindowsSdkIdentityPath = $paths.sdk
        }
        $command = Get-Command -Name Get-BuildToolchainAttestation -ErrorAction Stop
        Assert-True ($command.Parameters.ContainsKey('IdentityReader')) 'Toolchain attestation must support a bounded identity reader for native tools.'
        if (-not $command.Parameters.ContainsKey('IdentityReader')) { return }
        $entries = @(Get-BuildToolchainAttestation -Tools $tools -CmakePath $paths.cmake -IdentityReader { param($name, $path) return ('version-' + $name) })
        foreach ($name in @('msbuild', 'cmake', 'cl', 'link', 'rc', 'windows-sdk')) {
            Assert-True ($entries.name -contains $name) "Toolchain attestation must bind $name."
        }
        foreach ($entry in $entries) { Assert-True ([string]$entry.sha256 -match '^[A-F0-9]{64}$') "Toolchain entry $($entry.name) must bind executable/input bytes." }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-DependencyLibraryHashesAreStableAcrossProductBuild {
    $root = New-FixtureRoot
    try {
        $library = Join-Path $root 'fixture.lib'; [IO.File]::WriteAllText($library, 'before-link', [Text.Encoding]::ASCII)
        $plan = @([pscustomobject]@{ Name = 'fixture'; LibraryPath = $library })
        $before = @(Get-DependencyLibraryAttestation -Plan $plan)
        $command = Get-Command -Name Assert-DependencyLibraryAttestationUnchanged -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Candidate build must verify that pre-link library hashes remain unchanged after product build.'
        if ($null -eq $command) { return }
        Assert-DependencyLibraryAttestationUnchanged -Plan $plan -Before $before
        [IO.File]::WriteAllText($library, 'after-link', [Text.Encoding]::ASCII)
        try { Assert-DependencyLibraryAttestationUnchanged -Plan $plan -Before $before; $actual = 'no_failure' }
        catch { $actual = $_.Exception.Message }
        Assert-Equal 'dependency_linker_input_changed' $actual 'A dependency library mutation across product link must invalidate the candidate.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-CandidateManifestSealRequiresSchemaAttestationAndExactInventory {
    $root = New-FixtureRoot
    try {
        $fixture = New-MinimalSealedCandidate -Root $root
        $command = Get-Command -Name Assert-CandidateManifestSeal -ErrorAction SilentlyContinue
        Assert-True ($null -ne $command) 'Build and smoke must share a candidate manifest seal validator.'
        if ($null -eq $command) { return }
        Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest
        $fixture.Manifest.Remove('schemaVersion')
        try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $schemaResult = 'no_failure' } catch { $schemaResult = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_invalid' $schemaResult 'A candidate manifest without schemaVersion must be rejected.'
        $fixture.Manifest.schemaVersion = 1; $fixture.Manifest.Remove('attestation')
        try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $attestationResult = 'no_failure' } catch { $attestationResult = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_invalid' $attestationResult 'A candidate manifest without required build attestation must be rejected.'
        $fixture.Manifest.attestation = New-FixtureBuildAttestation
        $versions = $fixture.Manifest.versions; $fixture.Manifest.Remove('versions')
        try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $versionsResult = 'no_failure' } catch { $versionsResult = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_invalid' $versionsResult 'A candidate manifest without executable version evidence must be rejected.'
        $fixture.Manifest.versions = $versions
        $fixture.Manifest.attestation.commands[0].effectiveProperties.Remove('ImportDirectoryBuildProps')
        try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $propertiesResult = 'no_failure' } catch { $propertiesResult = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_invalid' $propertiesResult 'Build command evidence without the hermetic import policy must be rejected.'
        $fixture.Manifest.attestation = New-FixtureBuildAttestation
        [IO.File]::WriteAllText((Join-Path $fixture.Root 'extra.bin'), 'unmanifested', [Text.Encoding]::ASCII)
        try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $extraResult = 'no_failure' } catch { $extraResult = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_mismatch' $extraResult 'An extra unmanifested candidate file must invalidate the exact inventory.'
        Remove-Item -LiteralPath (Join-Path $fixture.Root 'extra.bin') -Force
        $nested = Join-Path $fixture.Root 'nested'; [IO.Directory]::CreateDirectory($nested) | Out-Null
        [IO.File]::WriteAllText((Join-Path $nested 'candidate-manifest.json'), 'nested-extra', [Text.Encoding]::ASCII)
        try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $nestedResult = 'no_failure' } catch { $nestedResult = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_mismatch' $nestedResult 'Only the root manifest file may be excluded from the exact payload inventory.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-CandidateManifestAttestationInventoriesAreExactSets {
    $root = New-FixtureRoot
    try {
        foreach ($case in @('linker-missing', 'linker-extra', 'toolchain-duplicate', 'toolchain-extra', 'command-missing', 'command-duplicate', 'command-extra')) {
            $fixture = New-MinimalSealedCandidate -Root (Join-Path $root $case)
            $attestation = $fixture.Manifest.attestation
            switch ($case) {
                'linker-missing' { $attestation.linkerInputs = @($attestation.linkerInputs | Select-Object -Skip 1) }
                'linker-extra' { $attestation.linkerInputs += [ordered]@{ name = 'rogue'; library = 'rogue.lib'; sha256 = ('E' * 64); length = 1 } }
                'toolchain-duplicate' { $attestation.toolchain += $attestation.toolchain[0] }
                'toolchain-extra' { $attestation.toolchain += [ordered]@{ name = 'rogue'; sha256 = ('E' * 64); version = '1' } }
                'command-missing' { $attestation.commands = @($attestation.commands | Select-Object -Skip 1) }
                'command-duplicate' { $attestation.commands += $attestation.commands[0] }
                'command-extra' { $extra = $attestation.commands[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json; $extra.name = 'rogue build'; $attestation.commands += $extra }
            }
            try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $actual = 'no_failure' } catch { $actual = $_.Exception.Message }
            Assert-Equal 'candidate_manifest_invalid' $actual "Attestation inventory case $case must be rejected as a non-exact set."
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-CandidateManifestCommandsRequireExactSemantics {
    $root = New-FixtureRoot
    try {
        foreach ($case in @('wrong-executable', 'missing-release', 'missing-solution', 'configure-globals-missing', 'configure-globals-duplicate', 'configure-globals-incomplete', 'build-shape', 'product-shape')) {
            $fixture = New-MinimalSealedCandidate -Root (Join-Path $root $case)
            $commands = $fixture.Manifest.attestation.commands
            $bit7z = $commands | Where-Object name -eq 'bit7z Release x64 build'
            $configure = $commands | Where-Object name -eq 'libjpeg-turbo Release x64 configure'
            $jpegBuild = $commands | Where-Object name -eq 'libjpeg-turbo Release x64 build'
            $product = $commands | Where-Object name -eq 'Release x64 MSBuild'
            switch ($case) {
                'wrong-executable' { $bit7z.executable = 'cmd.exe' }
                'missing-release' { $bit7z.arguments = @('<source>\bit7z\bit7z.sln', '/t:Build', '/p:Platform=x64') }
                'missing-solution' { $bit7z.arguments = @('/t:Build', '/p:Configuration=Release', '/p:Platform=x64') }
                'configure-globals-missing' { $configure.arguments = @($configure.arguments | Where-Object { $_ -notlike '-DCMAKE_VS_GLOBALS=*' }) }
                'configure-globals-duplicate' { $configure.arguments += @($configure.arguments | Where-Object { $_ -like '-DCMAKE_VS_GLOBALS=*' })[0] }
                'configure-globals-incomplete' { $configure.arguments[-1] = '-DCMAKE_VS_GLOBALS=ImportDirectoryBuildProps=false' }
                'build-shape' { $jpegBuild.arguments = @('--config', 'Release') }
                'product-shape' { $product.arguments = @('/t:Build', '/p:Configuration=Release', '/p:Platform=x64') }
            }
            try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $actual = 'no_failure' } catch { $actual = $_.Exception.Message }
            Assert-Equal 'candidate_manifest_invalid' $actual "Command semantic case $case must be rejected."
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-CandidateManifestCommandsRejectRogueOperands {
    $root = New-FixtureRoot
    try {
        foreach ($name in @('bit7z Release x64 build', 'Nana Release x64 build', 'libpng Release x64 build', 'libjpeg-turbo Release x64 configure', 'libjpeg-turbo Release x64 build', 'Release x64 MSBuild')) {
            $fixture = New-MinimalSealedCandidate -Root (Join-Path $root ([Guid]::NewGuid().ToString('N')))
            $command = $fixture.Manifest.attestation.commands | Where-Object name -eq $name
            $rogue = if ($name -like 'libjpeg-turbo Release x64 configure') { '-S=<source>\rogue' }
                elseif ($name -like 'libjpeg-turbo Release x64 build') { '<source>\rogue-build-dir' }
                else { '<source>\rogue\rogue.sln' }
            $command.arguments += $rogue
            try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $actual = 'no_failure' } catch { $actual = $_.Exception.Message }
            Assert-Equal 'candidate_manifest_invalid' $actual "Command $name must reject rogue operand $rogue."
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-CandidateManifestCommandsBindHermeticValues {
    $root = New-FixtureRoot
    try {
        foreach ($case in @('user-root-suffix', 'msvc-version-mismatch', 'sdk-version-mismatch', 'configure-global-mismatch')) {
            $fixture = New-MinimalSealedCandidate -Root (Join-Path $root ([Guid]::NewGuid().ToString('N')))
            $commands = $fixture.Manifest.attestation.commands
            $bit7z = $commands | Where-Object name -eq 'bit7z Release x64 build'
            $configure = $commands | Where-Object name -eq 'libjpeg-turbo Release x64 configure'
            switch ($case) {
                'user-root-suffix' {
                    $bit7z.arguments[7] = '/p:UserRootDir=<hermetic-user-root>\rogue'
                }
                'msvc-version-mismatch' {
                    $bit7z.arguments[8] = '/p:VCToolsVersion=99.99.99'
                }
                'sdk-version-mismatch' {
                    $bit7z.arguments[9] = '/p:WindowsTargetPlatformVersion=99.99.99'
                }
                'configure-global-mismatch' {
                    $configure.arguments[10] = $configure.arguments[10].Replace('VCToolsVersion=14.40.1', 'VCToolsVersion=99.99.99')
                }
            }
            try { Assert-CandidateManifestSeal -CandidateRoot $fixture.Root -Manifest $fixture.Manifest; $actual = 'no_failure' } catch { $actual = $_.Exception.Message }
            Assert-Equal 'candidate_manifest_invalid' $actual "Hermetic value case $case must be rejected."
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SmokeConsumerEnforcesBuildAttestationAndExactInventory {
    $root = New-FixtureRoot
    try {
        $fixture = New-MinimalSealedCandidate -Root $root
        [IO.File]::WriteAllText((Join-Path $fixture.Root 'extra.bin'), 'unmanifested', [Text.Encoding]::ASCII)
        $workspace = Join-Path $root 'workspace'; [IO.Directory]::CreateDirectory($workspace) | Out-Null
        try { Copy-SealedCandidateForSmoke -CandidateRoot $fixture.Root -Workspace $workspace | Out-Null; $extraResult = 'no_failure' } catch { $extraResult = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_mismatch' $extraResult 'Smoke consumer must reject extra candidate bytes omitted from the manifest.'

        Remove-Item -LiteralPath (Join-Path $fixture.Root 'extra.bin') -Force
        $fixture.Manifest.Remove('attestation')
        [IO.File]::WriteAllText($fixture.ManifestPath, ($fixture.Manifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        $workspaceTwo = Join-Path $root 'workspace-two'; [IO.Directory]::CreateDirectory($workspaceTwo) | Out-Null
        try { Copy-SealedCandidateForSmoke -CandidateRoot $fixture.Root -Workspace $workspaceTwo | Out-Null; $attestationResult = 'no_failure' } catch { $attestationResult = $_.Exception.Message }
        Assert-Equal 'candidate_manifest_invalid' $attestationResult 'Smoke consumer must reject a manifest without build attestation.'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

$buildAttestationRedTests = @(
    'Test-BuildSourceMaterializesTrackedFilesOnly',
    'Test-SourceInputAttestationRejectsDirtyAndBindsExactTree',
    'Test-HermeticBuildContextDisablesExternalPropsAndBindsEffectiveContext',
    'Test-ToolchainAttestationIncludesNativeCompilerLinkerResourceCompilerAndSdk',
    'Test-DependencyLibraryHashesAreStableAcrossProductBuild',
    'Test-CandidateManifestSealRequiresSchemaAttestationAndExactInventory',
    'Test-CandidateManifestAttestationInventoriesAreExactSets',
    'Test-CandidateManifestCommandsRequireExactSemantics',
    'Test-CandidateManifestCommandsRejectRogueOperands',
    'Test-CandidateManifestCommandsBindHermeticValues',
    'Test-SmokeConsumerEnforcesBuildAttestationAndExactInventory'
)

$sealRedTests = @(
    'Test-SmokeRejectsCallerExpectedManifestDigestMismatch',
    'Test-SmokeRejectsDuplicatePathsAndMalformedManifestMetadata',
    'Test-SmokeSettingsOverrideProducesExplicitDerivativeAttestation',
    'Test-SmokeExecutionOverlayRejectsBaseMismatchAndNonSettingsMutation',
    'Test-SmokeExecutionOverlayAllowsOnlyOutpathSettingsChange',
    'Test-SmokeExecutionOverlayRejectsBaseRootOverlap',
    'Test-SmokeEvidenceLivesOutsideCandidateAndPreservesWholeTree',
    'Test-CleanupFailureOnFailedRunIsRecordedAndThrown',
    'Test-SmokeSuccessEvidenceSeparatesProofClaims',
    'Test-SmokeBindsDetailedArtifactEvidenceBeforeDeletingWorkspace',
    'Test-SmokeCapturesSuccessEvidenceAfterCleanup'
)

if ($env:SMOKE_TEST_FILTER -ne 'seal-red' -and $env:SMOKE_TEST_FILTER -ne 'build-red') {
    Test-CandidateRootsAreUniqueAndContained
    Test-LocalhostOnlyUrls
    Test-FakeProcessesAreCleanedUp
    Test-FinalMp3AndPartRejection
    Test-SmokeOutputAcceptsWindowsFfprobeLineEndings
    Test-FailureEvidenceAndSuccessCleanup
    Test-CleanupTimeoutStillWritesSanitizedFailureEvidence
    Test-SmokeOutputRequiresFreshFiles
    Test-AutomationCompletionIsBoundToGuiUrlAndOutput
    Test-ParentOverlapAndSanitizedEvidenceAreRejected
    Test-SmokeManifestsAreAppendOnlyAndBindArtifactEvidence
    Test-SmokeOutputRootIsWrittenIntoCandidateSettings
    Test-SmokeExecutionCopyPreservesSealedCandidate
    Test-SmokeWorkspaceUsesDownloadsContainedRunRoot
    Test-DependencyArchiveAndRuntimeVerificationBoundaries
    Test-ExistingDependencyRootsCannotBypassArchiveRequirement
    Test-IsolatedBuildSourceExcludesExistingDependencyRoots
    Test-IsolatedBuildWorkspaceUsesConfiguredShortBase
    Test-ParentProvenanceRequiresRollbackIdentity
    Test-BackupVersionVerificationRunsNonExeBackupFromTemporaryExecutable
    Test-SourceAttestationBindsGitRevisionAndWorktreeState
    Test-DependencyLibraryAttestationBindsLinkerInputs
    Test-BuildCommandAttestationIncludesDependenciesWithoutAbsoluteSourcePaths
    Test-CheckedProcessUsesExitCodeAndCapturesOutput
    Test-ProcessEnvironmentNormalizesDuplicatePathKeys
    Test-SmokeProcessFailuresMapToStableReasonCodes
    Test-ReleaseX64DependencyPlanBuildsAndValidatesProductLibraries
}

if ($env:SMOKE_TEST_FILTER -ne 'build-red') { foreach ($testName in $sealRedTests) { & $testName } }
if ($env:SMOKE_TEST_FILTER -ne 'seal-red') { foreach ($testName in $buildAttestationRedTests) { & $testName } }

if ($script:failures.Count -ne 0) { $script:failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }; exit 1 }
Write-Output 'smoke-localhost fixture tests passed.'
