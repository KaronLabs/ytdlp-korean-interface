#requires -Version 7.4

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:Verifier = Join-Path $script:RepositoryRoot 'tools\verify-gui-release-evidence.ps1'
$script:Recorder = Join-Path $script:RepositoryRoot 'tools\record-gui-release-evidence.ps1'
$script:Pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$script:ReleaseVersion = 'v2.19.1-karon.2'
$script:ExpectedCases = @('ko-KR-100', 'ko-KR-150', 'ko-KR-200', 'en-US-100', 'en-US-150', 'en-US-200')
$script:ObservationNames = @(
    'launch',
    'downloadType',
    'quality1080p',
    'quality720p',
    'qualityBest',
    'expectedResolution',
    'queueRegistration',
    'progress',
    'completion',
    'advancedNavigation',
    'noClipping'
)
$script:FixtureRoots = [Collections.Generic.List[string]]::new()

function New-TestDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('karon-gui-evidence-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    $script:FixtureRoots.Add($path)
    $path
}

function ConvertTo-UtcText {
    param([DateTimeOffset] $Value)
    $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
}

function Write-TestJson {
    param([string] $Path, [object] $Value)
    $json = $Value | ConvertTo-Json -Depth 64
    [IO.File]::WriteAllText($Path, ($json.Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-TestSha256 {
    param([string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-TestScript {
    param([string] $ScriptPath, [string[]] $Arguments)

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "production_script_missing: $ScriptPath"
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:Pwsh
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($ScriptPath)
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'test_process_start_failed' }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = $stdout
        Error = $stderr
        Combined = $stdout + "`n" + $stderr
    }
}

function New-ObservationSet {
    param([string] $ObservedAtUtc)
    $result = [ordered]@{}
    foreach ($name in $script:ObservationNames) {
        $result[$name] = [ordered]@{ result = $true; observedAtUtc = $ObservedAtUtc }
    }
    $result
}

function New-ValidGuiFixture {
    $root = New-TestDirectory
    $evidence = Join-Path $root 'evidence'
    $cases = Join-Path $evidence 'cases'
    $screenshots = Join-Path $evidence 'screenshots'
    $artifacts = Join-Path $evidence 'artifacts'
    $output = Join-Path $root 'output'
    New-Item -ItemType Directory -Path $evidence, $cases, $screenshots, $artifacts, $output | Out-Null

    $exe = Join-Path $root 'ytdlp-interface.exe'
    [IO.File]::WriteAllBytes($exe, [Text.Encoding]::ASCII.GetBytes('sealed-candidate-fixture'))
    $exeInfo = Get-Item -LiteralPath $exe
    $exeSha = Get-TestSha256 $exe

    $now = [DateTimeOffset]::UtcNow
    $started = ConvertTo-UtcText $now.AddMinutes(-12)
    $observed = ConvertTo-UtcText $now.AddMinutes(-6)
    $completed = ConvertTo-UtcText $now.AddMinutes(-2)
    $pngBytes = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')

    foreach ($caseId in $script:ExpectedCases) {
        $parts = $caseId.Split('-')
        $language = $parts[0] + '-' + $parts[1]
        $dpi = [int]$parts[2]
        $screenshotRelative = "screenshots/$caseId-main.png"
        $screenshotPath = Join-Path $evidence ($screenshotRelative.Replace('/', '\'))
        [IO.File]::WriteAllBytes($screenshotPath, $pngBytes)
        $screenshotInfo = Get-Item -LiteralPath $screenshotPath

        $lifecycle = $null
        if ($caseId -in @('ko-KR-100', 'en-US-200')) {
            $mediaRelative = "artifacts/$caseId-video.mp4"
            $probeRelative = "artifacts/$caseId-ffprobe.json"
            $mediaPath = Join-Path $evidence ($mediaRelative.Replace('/', '\'))
            $probePath = Join-Path $evidence ($probeRelative.Replace('/', '\'))
            [IO.File]::WriteAllBytes($mediaPath, [Text.Encoding]::ASCII.GetBytes("media-$caseId"))
            Write-TestJson $probePath ([ordered]@{
                streams = @(
                    [ordered]@{ codec_type = 'video'; width = 1920; height = 1080 },
                    [ordered]@{ codec_type = 'audio'; channels = 2 }
                )
            })
            $mediaInfo = Get-Item -LiteralPath $mediaPath
            $probeInfo = Get-Item -LiteralPath $probePath
            $lifecycle = [ordered]@{
                completed = $true
                observedAtUtc = $observed
                expectedWidth = 1920
                expectedHeight = 1080
                output = [ordered]@{ path = $mediaRelative; sha256 = Get-TestSha256 $mediaPath; length = $mediaInfo.Length }
                ffprobe = [ordered]@{ path = $probeRelative; sha256 = Get-TestSha256 $probePath; length = $probeInfo.Length }
            }
        }

        $representative = [ordered]@{
            mp3Conversion = $null
            settingsSaveRestartRestore = $null
            legacySettingsTransition = $null
        }
        if ($caseId -eq 'ko-KR-100') {
            $mp3Relative = 'artifacts/ko-KR-100-audio.mp3'
            $mp3Path = Join-Path $evidence ($mp3Relative.Replace('/', '\'))
            [IO.File]::WriteAllBytes($mp3Path, [Text.Encoding]::ASCII.GetBytes('mp3-fixture'))
            $mp3Info = Get-Item -LiteralPath $mp3Path
            $representative.mp3Conversion = [ordered]@{
                result = $true
                observedAtUtc = $observed
                output = [ordered]@{ path = $mp3Relative; sha256 = Get-TestSha256 $mp3Path; length = $mp3Info.Length }
            }
            $representative.settingsSaveRestartRestore = [ordered]@{
                result = $true
                observedAtUtc = $observed
                screenshotPath = $screenshotRelative
            }
        }
        if ($caseId -eq 'en-US-200') {
            $representative.legacySettingsTransition = [ordered]@{
                result = $true
                observedAtUtc = $observed
                screenshotPath = $screenshotRelative
            }
        }

        $case = [ordered]@{
            schemaVersion = 1
            releaseVersion = $script:ReleaseVersion
            caseId = $caseId
            language = $language
            dpiPercent = $dpi
            startedAtUtc = $started
            completedAtUtc = $completed
            executable = [ordered]@{ fileName = 'ytdlp-interface.exe'; sha256 = $exeSha; length = $exeInfo.Length }
            environment = [ordered]@{ observedLanguage = $language; observedDpiPercent = $dpi; recordedAtUtc = $observed }
            observations = New-ObservationSet $observed
            screenshots = @([ordered]@{
                path = $screenshotRelative
                sha256 = Get-TestSha256 $screenshotPath
                length = $screenshotInfo.Length
                width = 1
                height = 1
                capturedAtUtc = $observed
            })
            fullVideoLifecycle = $lifecycle
            representativeChecks = $representative
            notes = ''
        }
        Write-TestJson (Join-Path $cases "$caseId.json") $case
    }

    [pscustomobject]@{
        Root = $root
        Evidence = $evidence
        Cases = $cases
        Screenshots = $screenshots
        Artifacts = $artifacts
        Output = $output
        Exe = $exe
        ExeSha = $exeSha
    }
}

function Read-TestCase {
    param([object] $Fixture, [string] $CaseId)
    $path = Join-Path $Fixture.Cases "$CaseId.json"
    [pscustomobject]@{ Path = $path; Value = (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64 -DateKind String) }
}

function Save-TestCase {
    param([object] $Case)
    Write-TestJson $Case.Path $Case.Value
}

function Invoke-GuiVerifier {
    param([object] $Fixture, [string] $OutputDirectory = $Fixture.Output)
    Invoke-TestScript $script:Verifier @(
        '-EvidenceRoot', $Fixture.Evidence,
        '-CandidateExePath', $Fixture.Exe,
        '-OutputDirectory', $OutputDirectory,
        '-MaximumEvidenceAgeHours', '24'
    )
}

function Assert-VerifierRejects {
    param([object] $Fixture, [string] $Pattern)
    $result = Invoke-GuiVerifier $Fixture
    $result.ExitCode | Should Not Be 0
    $result.Combined | Should Match $Pattern
    (Test-Path -LiteralPath (Join-Path $Fixture.Output 'gui-validation-v2.19.1-karon.2')) | Should Be $false
}

function Set-ProbeStreams {
    param([object] $Fixture, [object[]] $Streams)
    $case = Read-TestCase $Fixture 'ko-KR-100'
    $relative = [string]$case.Value.fullVideoLifecycle.ffprobe.path
    $path = Join-Path $Fixture.Evidence ($relative.Replace('/', '\'))
    Write-TestJson $path ([ordered]@{ streams = $Streams })
    $info = Get-Item -LiteralPath $path
    $case.Value.fullVideoLifecycle.ffprobe.sha256 = Get-TestSha256 $path
    $case.Value.fullVideoLifecycle.ffprobe.length = $info.Length
    Save-TestCase $case
}

Describe 'v2.19.1-karon.2 GUI release evidence contract' {
    AfterAll {
        foreach ($root in $script:FixtureRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts exactly six complete cases and emits deterministic summary and manifest bytes' {
        $fixture = New-ValidGuiFixture
        $first = Invoke-GuiVerifier $fixture
        $first.ExitCode | Should Be 0
        $final = Join-Path $fixture.Output 'gui-validation-v2.19.1-karon.2'
        $summary = Join-Path $final 'gui-validation-summary.json'
        $manifest = Join-Path $final 'gui-validation-evidence-manifest.json'
        (Test-Path -LiteralPath $summary -PathType Leaf) | Should Be $true
        (Test-Path -LiteralPath $manifest -PathType Leaf) | Should Be $true

        $summaryValue = Get-Content -LiteralPath $summary -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64
        $summaryValue.status | Should Be 'PASS'
        $summaryValue.executableSha256 | Should Be $fixture.ExeSha
        @($summaryValue.cases).Count | Should Be 6
        (@($summaryValue.cases) -join ',') | Should Be ($script:ExpectedCases -join ',')

        $secondOutput = Join-Path $fixture.Root 'second-output'
        New-Item -ItemType Directory -Path $secondOutput | Out-Null
        $second = Invoke-GuiVerifier $fixture $secondOutput
        $second.ExitCode | Should Be 0
        $secondFinal = Join-Path $secondOutput 'gui-validation-v2.19.1-karon.2'
        (Get-TestSha256 $summary) | Should Be (Get-TestSha256 (Join-Path $secondFinal 'gui-validation-summary.json'))
        (Get-TestSha256 $manifest) | Should Be (Get-TestSha256 (Join-Path $secondFinal 'gui-validation-evidence-manifest.json'))
    }

    It 'rejects a missing required case' {
        $fixture = New-ValidGuiFixture
        Remove-Item -LiteralPath (Join-Path $fixture.Cases 'en-US-150.json')
        Assert-VerifierRejects $fixture 'gui_case_count_invalid|gui_case_set_invalid'
    }

    It 'rejects an extra case' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'en-US-150'
        $case.Value.caseId = 'fr-FR-100'
        Write-TestJson (Join-Path $fixture.Cases 'fr-FR-100.json') $case.Value
        Assert-VerifierRejects $fixture 'gui_case_count_invalid|gui_case_set_invalid'
    }

    It 'rejects duplicate case identities' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'en-US-100'
        $case.Value.caseId = 'ko-KR-100'
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_case_duplicate'
    }

    It 'rejects stale case evidence' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $case.Value.startedAtUtc = '2020-01-01T00:00:00.000Z'
        $case.Value.completedAtUtc = '2020-01-01T00:10:00.000Z'
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_evidence_stale'
    }

    It 'rejects a missing referenced screenshot' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $case.Value.screenshots[0].path = 'screenshots/does-not-exist.png'
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_evidence_file_missing'
    }

    It 'rejects mixed executable SHA values' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $case.Value.executable.sha256 = ('a' * 64)
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_executable_sha_mixed'
    }

    It 'rejects a uniform executable SHA that does not match the candidate bytes' {
        $fixture = New-ValidGuiFixture
        foreach ($caseId in $script:ExpectedCases) {
            $case = Read-TestCase $fixture $caseId
            $case.Value.executable.sha256 = ('b' * 64)
            Save-TestCase $case
        }
        Assert-VerifierRejects $fixture 'gui_executable_hash_mismatch'
    }

    It 'rejects the wrong observed language' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $case.Value.environment.observedLanguage = 'en-US'
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_language_mismatch'
    }

    It 'rejects the wrong observed DPI' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'en-US-150'
        $case.Value.environment.observedDpiPercent = 100
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_dpi_mismatch'
    }

    It 'rejects a false required observation' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-200'
        $case.Value.observations.progress.result = $false
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_observation_failed'
    }

    It 'rejects a non-boolean required observation' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-200'
        $case.Value.observations.progress.result = 'true'
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_observation_not_boolean'
    }

    It 'rejects any clipped UI observation' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'en-US-200'
        $case.Value.observations.noClipping.result = $false
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_clipping_detected'
    }

    It 'rejects a missing ffprobe artifact for a required lifecycle case' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $probe = Join-Path $fixture.Evidence (([string]$case.Value.fullVideoLifecycle.ffprobe.path).Replace('/', '\'))
        Remove-Item -LiteralPath $probe
        Assert-VerifierRejects $fixture 'gui_evidence_file_missing'
    }

    It 'rejects ffprobe evidence without an audio stream' {
        $fixture = New-ValidGuiFixture
        Set-ProbeStreams $fixture @([ordered]@{ codec_type = 'video'; width = 1920; height = 1080 })
        Assert-VerifierRejects $fixture 'gui_ffprobe_audio_missing'
    }

    It 'rejects ffprobe evidence without a video stream' {
        $fixture = New-ValidGuiFixture
        Set-ProbeStreams $fixture @([ordered]@{ codec_type = 'audio'; channels = 2 })
        Assert-VerifierRejects $fixture 'gui_ffprobe_video_missing'
    }

    It 'rejects a false lifecycle completion value' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'en-US-200'
        $case.Value.fullVideoLifecycle.completed = $false
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_lifecycle_failed'
    }

    It 'rejects screenshot hash mismatch' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        $bytes = [IO.File]::ReadAllBytes($path)
        $bytes[$bytes.Length - 1] = $bytes[$bytes.Length - 1] -bxor 1
        [IO.File]::WriteAllBytes($path, $bytes)
        Assert-VerifierRejects $fixture 'gui_evidence_hash_mismatch'
    }

    It 'rejects screenshot dimension mismatch' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $case.Value.screenshots[0].width = 2
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_dimensions_mismatch'
    }

    It 'rejects a screenshot timestamp outside its case interval' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $case.Value.screenshots[0].capturedAtUtc = '2020-01-01T00:00:00.000Z'
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_timestamp_outside_case|gui_evidence_stale'
    }

    It 'rejects an artifact length or hash mismatch' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $case.Value.fullVideoLifecycle.output.length = [long]$case.Value.fullVideoLifecycle.output.length + 1
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_evidence_length_mismatch'
    }

    It 'rejects missing MP3 representative coverage' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $case.Value.representativeChecks.mp3Conversion = $null
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_representative_check_missing: mp3Conversion'
    }

    It 'rejects missing settings save and restart coverage' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $case.Value.representativeChecks.settingsSaveRestartRestore = $null
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_representative_check_missing: settingsSaveRestartRestore'
    }

    It 'rejects missing legacy settings transition coverage' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'en-US-200'
        $case.Value.representativeChecks.legacySettingsTransition = $null
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_representative_check_missing: legacySettingsTransition'
    }

    It 'rejects a false representative result' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $case.Value.representativeChecks.mp3Conversion.result = $false
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_representative_check_failed'
    }

    It 'rejects secret-like query URLs in evidence text' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $case.Value.notes = 'https://media.example.invalid/file?signature=secret&expires=9999999999'
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_secret_material_detected'
    }

    It 'preserves another producer final directory during a no-overwrite race' {
        $fixture = New-ValidGuiFixture
        $seedOutput = Join-Path $fixture.Root 'seed-output'
        New-Item -ItemType Directory -Path $seedOutput | Out-Null
        $seedResult = Invoke-GuiVerifier $fixture $seedOutput
        $seedResult.ExitCode | Should Be 0
        $seedFinal = Join-Path $seedOutput 'gui-validation-v2.19.1-karon.2'

        for ($i = 0; $i -lt 2000; $i++) {
            [IO.File]::WriteAllText((Join-Path $fixture.Evidence ("padding-{0:D4}.txt" -f $i)), 'evidence padding')
        }

        $raceOutput = Join-Path $fixture.Root 'race-output'
        New-Item -ItemType Directory -Path $raceOutput | Out-Null
        $raceFinal = Join-Path $raceOutput 'gui-validation-v2.19.1-karon.2'
        $watcherPath = Join-Path $fixture.Root 'watcher.ps1'
        $watcherText = @'
param([string]$OutputRoot,[string]$Seed,[string]$Final)
$deadline = [DateTime]::UtcNow.AddSeconds(20)
while ([DateTime]::UtcNow -lt $deadline) {
    if (@(Get-ChildItem -LiteralPath $OutputRoot -Directory -Filter '.gui-validation-v2.19.1-karon.2.partial.*' -ErrorAction SilentlyContinue).Count -gt 0) {
        Copy-Item -LiteralPath $Seed -Destination $Final -Recurse
        exit 0
    }
    Start-Sleep -Milliseconds 1
}
exit 2
'@
        [IO.File]::WriteAllText($watcherPath, $watcherText, [Text.UTF8Encoding]::new($false))
        $watcher = Start-Process -FilePath $script:Pwsh -ArgumentList @('-NoProfile', '-File', $watcherPath, $raceOutput, $seedFinal, $raceFinal) -PassThru -WindowStyle Hidden
        $raceResult = Invoke-GuiVerifier $fixture $raceOutput
        $watcher.WaitForExit()

        $watcher.ExitCode | Should Be 0
        $raceResult.ExitCode | Should Not Be 0
        $raceResult.Combined | Should Match 'gui_validation_output_race'
        (Test-Path -LiteralPath $raceFinal -PathType Container) | Should Be $true
        (Get-TestSha256 (Join-Path $raceFinal 'gui-validation-summary.json')) | Should Be (Get-TestSha256 (Join-Path $seedFinal 'gui-validation-summary.json'))
        (Get-TestSha256 (Join-Path $raceFinal 'gui-validation-evidence-manifest.json')) | Should Be (Get-TestSha256 (Join-Path $seedFinal 'gui-validation-evidence-manifest.json'))
        @(Get-ChildItem -LiteralPath $raceOutput -Directory -Filter '.gui-validation-v2.19.1-karon.2.partial.*').Count | Should Be 0
    }

    It 'initializes an operator case with no preset observations or environment PASS values' {
        $root = New-TestDirectory
        $evidence = Join-Path $root 'operator-evidence'
        $exe = Join-Path $root 'ytdlp-interface.exe'
        [IO.File]::WriteAllText($exe, 'operator-fixture')
        $result = Invoke-TestScript $script:Recorder @(
            '-Action', 'Initialize',
            '-EvidenceRoot', $evidence,
            '-CandidateExePath', $exe,
            '-Language', 'ko-KR',
            '-DpiPercent', '100'
        )
        $result.ExitCode | Should Be 0
        $case = Get-Content -LiteralPath (Join-Path $evidence 'cases\ko-KR-100.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64
        $case.completedAtUtc | Should Be $null
        $case.environment.observedLanguage | Should Be $null
        $case.environment.observedDpiPercent | Should Be $null
        foreach ($name in $script:ObservationNames) { $case.observations.$name | Should Be $null }
        $case.representativeChecks.mp3Conversion | Should Be $null
        $case.representativeChecks.settingsSaveRestartRestore | Should Be $null
        $case.representativeChecks.legacySettingsTransition | Should Be $null
    }
}
