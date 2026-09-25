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
    'launch', 'downloadType', 'quality1080p', 'quality720p', 'qualityBest', 'expectedResolution',
    'queueRegistration', 'progress', 'completion', 'advancedNavigation', 'noClipping'
)
$script:FixtureRoots = [Collections.Generic.List[string]]::new()
$script:Media = $null

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

function Find-TestRuntimeTool {
    param([string] $Name)
    $projectParent = Split-Path -Parent (Split-Path -Parent $script:RepositoryRoot)
    $candidates = [Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:KARON_TEST_FFMPEG_DIR)) {
        $candidates.Add((Join-Path $env:KARON_TEST_FFMPEG_DIR $Name))
    }
    foreach ($root in @($script:RepositoryRoot, (Split-Path -Parent $script:RepositoryRoot), $projectParent)) {
        $candidates.Add((Join-Path $root $Name))
    }
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) { $candidates.Add($command.Source) }
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $item = Get-Item -LiteralPath $path
            if ($item.Length -gt 0) { return $item.FullName }
        }
    }
    throw "test_runtime_tool_missing: $Name"
}

function Invoke-NativeChecked {
    param([string] $Path, [string[]] $Arguments)
    $output = & $Path @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "fixture_command_failed: $Path exit=$LASTEXITCODE $output" }
}

function Initialize-TestMedia {
    $root = New-TestDirectory
    $ffmpeg = Find-TestRuntimeTool 'ffmpeg.exe'
    $ffprobeSource = Find-TestRuntimeTool 'ffprobe.exe'
    $ffprobe = Join-Path $root 'ffprobe.exe'
    Copy-Item -LiteralPath $ffprobeSource -Destination $ffprobe

    $validVideo = Join-Path $root 'valid-video.mp4'
    $videoOnly = Join-Path $root 'video-only.mp4'
    $audioOnly = Join-Path $root 'audio-only.mp4'
    $validMp3 = Join-Path $root 'valid-audio.mp3'
    Invoke-NativeChecked $ffmpeg @(
        '-hide_banner', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'color=c=black:s=1920x1080:r=1:d=1',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
        '-c:v', 'mpeg4', '-q:v', '20', '-c:a', 'aac', '-shortest', '-y', $validVideo
    )
    Invoke-NativeChecked $ffmpeg @(
        '-hide_banner', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'color=c=black:s=1920x1080:r=1:d=1',
        '-c:v', 'mpeg4', '-q:v', '20', '-an', '-y', $videoOnly
    )
    Invoke-NativeChecked $ffmpeg @(
        '-hide_banner', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
        '-c:a', 'aac', '-vn', '-y', $audioOnly
    )
    Invoke-NativeChecked $ffmpeg @(
        '-hide_banner', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
        '-c:a', 'libmp3lame', '-y', $validMp3
    )

    Add-Type -AssemblyName System.Drawing
    $validPng = Join-Path $root 'screen-640x480.png'
    $smallPng = Join-Path $root 'screen-1x1.png'
    $bitmap = [Drawing.Bitmap]::new(640, 480)
    try { $bitmap.Save($validPng, [Drawing.Imaging.ImageFormat]::Png) }
    finally { $bitmap.Dispose() }
    $bitmap = [Drawing.Bitmap]::new(1, 1)
    try { $bitmap.Save($smallPng, [Drawing.Imaging.ImageFormat]::Png) }
    finally { $bitmap.Dispose() }

    $script:Media = [pscustomobject]@{
        Ffprobe = $ffprobe
        ValidVideo = $validVideo
        VideoOnly = $videoOnly
        AudioOnly = $audioOnly
        ValidMp3 = $validMp3
        ValidPng = $validPng
        SmallPng = $smallPng
    }
}

function New-TestCandidate {
    param([string] $Root)
    $candidate = Join-Path $Root 'candidate'
    New-Item -ItemType Directory -Path $candidate | Out-Null
    $exe = Join-Path $candidate 'ytdlp-interface.exe'
    $ffprobe = Join-Path $candidate 'ffprobe.exe'
    [IO.File]::WriteAllBytes($exe, [Text.Encoding]::ASCII.GetBytes('sealed-candidate-fixture'))
    New-Item -ItemType HardLink -Path $ffprobe -Target $script:Media.Ffprobe | Out-Null
    $files = @(
        [ordered]@{ path = 'ytdlp-interface.exe'; sha256 = Get-TestSha256 $exe; length = (Get-Item $exe).Length },
        [ordered]@{ path = 'ffprobe.exe'; sha256 = Get-TestSha256 $ffprobe; length = (Get-Item $ffprobe).Length }
    )
    $manifest = Join-Path $candidate 'candidate-manifest.json'
    Write-TestJson $manifest ([ordered]@{
        schemaVersion = 1
        createdAtUtc = ConvertTo-UtcText ([DateTimeOffset]::UtcNow)
        attestation = [ordered]@{}
        versions = [ordered]@{}
        files = $files
    })
    [pscustomobject]@{ Root = $candidate; Exe = $exe; Ffprobe = $ffprobe; Manifest = $manifest }
}

function Invoke-TestScript {
    param([string] $ScriptPath, [string[]] $Arguments)
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { throw "production_script_missing: $ScriptPath" }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:Pwsh
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', $ScriptPath) + $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'test_process_start_failed' }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout; Error = $stderr; Combined = $stdout + "`n" + $stderr }
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
    $candidate = New-TestCandidate $root
    $exeInfo = Get-Item -LiteralPath $candidate.Exe
    $exeSha = Get-TestSha256 $candidate.Exe

    $now = [DateTimeOffset]::UtcNow
    $started = ConvertTo-UtcText $now.AddMinutes(-12)
    $observed = ConvertTo-UtcText $now.AddMinutes(-6)
    $completed = ConvertTo-UtcText $now.AddMinutes(-2)

    foreach ($caseId in $script:ExpectedCases) {
        $parts = $caseId.Split('-')
        $language = $parts[0] + '-' + $parts[1]
        $dpi = [int]$parts[2]
        $screenshotRelative = "screenshots/$caseId-main.png"
        $screenshotPath = Join-Path $evidence ($screenshotRelative.Replace('/', '\'))
        Copy-Item -LiteralPath $script:Media.ValidPng -Destination $screenshotPath
        $screenshotInfo = Get-Item -LiteralPath $screenshotPath

        $lifecycle = $null
        if ($caseId -in @('ko-KR-100', 'en-US-200')) {
            $mediaRelative = "artifacts/$caseId-video.mp4"
            $mediaPath = Join-Path $evidence ($mediaRelative.Replace('/', '\'))
            Copy-Item -LiteralPath $script:Media.ValidVideo -Destination $mediaPath
            $mediaInfo = Get-Item -LiteralPath $mediaPath
            $lifecycle = [ordered]@{
                completed = $true
                observedAtUtc = $observed
                expectedWidth = 1920
                expectedHeight = 1080
                output = [ordered]@{ path = $mediaRelative; sha256 = Get-TestSha256 $mediaPath; length = $mediaInfo.Length }
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
            Copy-Item -LiteralPath $script:Media.ValidMp3 -Destination $mp3Path
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
            schemaVersion = 2
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
                width = 640
                height = 480
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
        Candidate = $candidate
        Exe = $candidate.Exe
        ExeSha = $exeSha
    }
}

function Read-TestCase {
    param([object] $Fixture, [string] $CaseId)
    $path = Join-Path $Fixture.Cases "$CaseId.json"
    [pscustomobject]@{
        Path = $path
        Value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64 -DateKind String
    }
}

function Save-TestCase {
    param([object] $Case)
    Write-TestJson $Case.Path $Case.Value
}

function Update-DescriptorForFile {
    param([object] $Descriptor, [string] $Path)
    $Descriptor.sha256 = Get-TestSha256 $Path
    $Descriptor.length = (Get-Item -LiteralPath $Path).Length
}

function Replace-LifecycleMedia {
    param([object] $Fixture, [string] $CaseId, [string] $Source)
    $case = Read-TestCase $Fixture $CaseId
    $path = Join-Path $Fixture.Evidence (([string]$case.Value.fullVideoLifecycle.output.path).Replace('/', '\'))
    Copy-Item -LiteralPath $Source -Destination $path -Force
    Update-DescriptorForFile $case.Value.fullVideoLifecycle.output $path
    Save-TestCase $case
}

function Replace-Mp3Media {
    param([object] $Fixture, [string] $Source)
    $case = Read-TestCase $Fixture 'ko-KR-100'
    $path = Join-Path $Fixture.Evidence (([string]$case.Value.representativeChecks.mp3Conversion.output.path).Replace('/', '\'))
    Copy-Item -LiteralPath $Source -Destination $path -Force
    Update-DescriptorForFile $case.Value.representativeChecks.mp3Conversion.output $path
    Save-TestCase $case
}

function Invoke-GuiVerifier {
    param([object] $Fixture, [string] $OutputDirectory = $Fixture.Output)
    Invoke-TestScript $script:Verifier @(
        '-EvidenceRoot', $Fixture.Evidence,
        '-CandidateExePath', $Fixture.Exe,
        '-CandidateManifestPath', $Fixture.Candidate.Manifest,
        '-OutputDirectory', $OutputDirectory,
        '-MaximumEvidenceAgeHours', '24'
    )
}

function Assert-VerifierRejects {
    param([object] $Fixture, [string] $Pattern)
    $result = Invoke-GuiVerifier $Fixture
    $result.ExitCode | Should -Not -Be 0
    $result.Combined | Should -Match $Pattern
    (Test-Path -LiteralPath (Join-Path $Fixture.Output 'gui-validation-v2.19.1-karon.2')) | Should -Be $false
}

function Start-TestInputMutation {
    param(
        [string] $OutputRoot,
        [string] $TargetPath,
        [ValidateSet('AppendText', 'CreateBinary')] [string] $Mutation
    )
    $watcherPath = Join-Path (Split-Path -Parent $OutputRoot) ('input-mutation-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    $watcherText = @'
param([string]$OutputRoot,[string]$TargetPath,[string]$Mutation)
$deadline = [DateTime]::UtcNow.AddSeconds(20)
while ([DateTime]::UtcNow -lt $deadline) {
    if (@(Get-ChildItem -LiteralPath $OutputRoot -Directory -Filter '.gui-validation-v2.19.1-karon.2.partial.*' -ErrorAction SilentlyContinue).Count -gt 0) {
        if ($Mutation -ceq 'AppendText') {
            [IO.File]::AppendAllText($TargetPath, 'mutated-after-snapshot', [Text.UTF8Encoding]::new($false))
        }
        else {
            [IO.File]::WriteAllBytes($TargetPath, [byte[]](0, 1, 2, 3, 255))
        }
        exit 0
    }
    Start-Sleep -Milliseconds 1
}
exit 2
'@
    [IO.File]::WriteAllText($watcherPath, $watcherText, [Text.UTF8Encoding]::new($false))
    Start-Process -FilePath $script:Pwsh -ArgumentList @(
        '-NoProfile', '-File', $watcherPath, $OutputRoot, $TargetPath, $Mutation
    ) -PassThru -WindowStyle Hidden
}

function Add-TestPngChunkBeforeIend {
    param([string] $Path, [byte[]] $Chunk)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 12) { throw 'test_png_too_short' }
    $result = [byte[]]::new($bytes.Length + $Chunk.Length)
    [Buffer]::BlockCopy($bytes, 0, $result, 0, $bytes.Length - 12)
    [Buffer]::BlockCopy($Chunk, 0, $result, $bytes.Length - 12, $Chunk.Length)
    [Buffer]::BlockCopy($bytes, $bytes.Length - 12, $result, $bytes.Length - 12 + $Chunk.Length, 12)
    [IO.File]::WriteAllBytes($Path, $result)
}

function New-TestPngChunk {
    param([string] $Type, [byte[]] $Data, [byte[]] $Crc)
    $typeBytes = [Text.Encoding]::ASCII.GetBytes($Type)
    $chunk = [byte[]]::new(12 + $Data.Length)
    $length = [uint32]$Data.Length
    $chunk[0] = [byte](($length -shr 24) -band 0xff)
    $chunk[1] = [byte](($length -shr 16) -band 0xff)
    $chunk[2] = [byte](($length -shr 8) -band 0xff)
    $chunk[3] = [byte]($length -band 0xff)
    [Buffer]::BlockCopy($typeBytes, 0, $chunk, 4, 4)
    if ($Data.Length -gt 0) { [Buffer]::BlockCopy($Data, 0, $chunk, 8, $Data.Length) }
    [Buffer]::BlockCopy($Crc, 0, $chunk, 8 + $Data.Length, 4)
    Write-Output -NoEnumerate $chunk
}

function Get-TestPngCrcBytes {
    param([string] $Type, [byte[]] $Data)
    $input = [byte[]]::new(4 + $Data.Length)
    [Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes($Type), 0, $input, 0, 4)
    if ($Data.Length -gt 0) { [Buffer]::BlockCopy($Data, 0, $input, 4, $Data.Length) }
    [uint32]$crc = 4294967295
    foreach ($byte in $input) {
        $crc = [uint32]($crc -bxor $byte)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 1) -ne 0) { $crc = [uint32](3988292384 -bxor ($crc -shr 1)) }
            else { $crc = [uint32]($crc -shr 1) }
        }
    }
    $crc = [uint32]($crc -bxor 4294967295)
    Write-Output -NoEnumerate ([byte[]](
        [byte](($crc -shr 24) -band 255),
        [byte](($crc -shr 16) -band 255),
        [byte](($crc -shr 8) -band 255),
        [byte]($crc -band 255)
    ))
}

function New-ValidTestPngChunk {
    param([string] $Type, [byte[]] $Data)
    $chunk = New-TestPngChunk $Type $Data (Get-TestPngCrcBytes $Type $Data)
    Write-Output -NoEnumerate $chunk
}

function Insert-TestBytes {
    param([string] $Path, [int] $Offset, [byte[]] $Inserted)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $result = [byte[]]::new($bytes.Length + $Inserted.Length)
    [Buffer]::BlockCopy($bytes, 0, $result, 0, $Offset)
    [Buffer]::BlockCopy($Inserted, 0, $result, $Offset, $Inserted.Length)
    [Buffer]::BlockCopy($bytes, $Offset, $result, $Offset + $Inserted.Length, $bytes.Length - $Offset)
    [IO.File]::WriteAllBytes($Path, $result)
}

function Get-TestPngChunkOffset {
    param([string] $Path, [string] $Type)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $offset = 8
    while ($offset + 12 -le $bytes.Length) {
        $length = ([int64]$bytes[$offset] -shl 24) -bor ([int64]$bytes[$offset + 1] -shl 16) -bor
            ([int64]$bytes[$offset + 2] -shl 8) -bor [int64]$bytes[$offset + 3]
        $currentType = [Text.Encoding]::ASCII.GetString($bytes, $offset + 4, 4)
        if ($currentType -ceq $Type) { return $offset }
        $offset = [int]($offset + 12 + $length)
    }
    throw "test_png_chunk_missing: $Type"
}

function Set-TestPngDimensions {
    param([string] $Path, [uint32] $Width, [uint32] $Height)
    $bytes = [IO.File]::ReadAllBytes($Path)
    foreach ($value in @(
        [pscustomobject]@{ offset = 16; number = $Width },
        [pscustomobject]@{ offset = 20; number = $Height }
    )) {
        $bytes[$value.offset] = [byte](($value.number -shr 24) -band 255)
        $bytes[$value.offset + 1] = [byte](($value.number -shr 16) -band 255)
        $bytes[$value.offset + 2] = [byte](($value.number -shr 8) -band 255)
        $bytes[$value.offset + 3] = [byte]($value.number -band 255)
    }
    $ihdrData = [byte[]]::new(13)
    [Buffer]::BlockCopy($bytes, 16, $ihdrData, 0, 13)
    $crc = Get-TestPngCrcBytes 'IHDR' $ihdrData
    [Buffer]::BlockCopy($crc, 0, $bytes, 29, 4)
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function Set-TestPngColorType {
    param([string] $Path, [byte] $ColorType)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bytes[25] = $ColorType
    $ihdrData = [byte[]]::new(13)
    [Buffer]::BlockCopy($bytes, 16, $ihdrData, 0, 13)
    $crc = Get-TestPngCrcBytes 'IHDR' $ihdrData
    [Buffer]::BlockCopy($crc, 0, $bytes, 29, 4)
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function Add-TestPngTransparencyBeforeIdat {
    param(
        [string] $Path,
        [byte] $ColorType,
        [byte[]] $Transparency,
        [byte[]] $Palette = $null
    )
    Set-TestPngColorType $Path $ColorType
    [byte[]]$paletteChunk = [byte[]]::new(0)
    if ($null -ne $Palette) { $paletteChunk = New-ValidTestPngChunk 'PLTE' $Palette }
    $transparencyChunk = New-ValidTestPngChunk 'tRNS' $Transparency
    $inserted = [byte[]]::new($paletteChunk.Length + $transparencyChunk.Length)
    if ($paletteChunk.Length -gt 0) { [Buffer]::BlockCopy($paletteChunk, 0, $inserted, 0, $paletteChunk.Length) }
    [Buffer]::BlockCopy($transparencyChunk, 0, $inserted, $paletteChunk.Length, $transparencyChunk.Length)
    Insert-TestBytes $Path (Get-TestPngChunkOffset $Path 'IDAT') $inserted
}

function Get-TestFunctionSource {
    param([string] $Path, [string] $Name)
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) { throw 'test_production_script_parse_failed' }
    $function = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name
    }, $true)
    if ($null -eq $function) { throw "test_production_function_missing: $Name" }
    $function.Extent.Text
}

Describe 'v2.19.1-karon.2 GUI release evidence contract' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:Verifier = Join-Path $script:RepositoryRoot 'tools\verify-gui-release-evidence.ps1'
        $script:Recorder = Join-Path $script:RepositoryRoot 'tools\record-gui-release-evidence.ps1'
        $script:Pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
        $script:ReleaseVersion = 'v2.19.1-karon.2'
        $script:ExpectedCases = @('ko-KR-100', 'ko-KR-150', 'ko-KR-200', 'en-US-100', 'en-US-150', 'en-US-200')
        $script:ObservationNames = @(
            'launch', 'downloadType', 'quality1080p', 'quality720p', 'qualityBest', 'expectedResolution',
            'queueRegistration', 'progress', 'completion', 'advancedNavigation', 'noClipping'
        )
        $script:FixtureRoots = [Collections.Generic.List[string]]::new()
        $script:Media = $null
        Initialize-TestMedia
    }

    AfterAll {
        foreach ($root in $script:FixtureRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts six complete cases, probes real media, and emits deterministic schema-v2 bytes' {
        $fixture = New-ValidGuiFixture
        $first = Invoke-GuiVerifier $fixture
        $first.ExitCode | Should -Be 0
        $final = Join-Path $fixture.Output 'gui-validation-v2.19.1-karon.2'
        $summary = Join-Path $final 'gui-validation-summary.json'
        $manifest = Join-Path $final 'gui-validation-evidence-manifest.json'
        (Test-Path -LiteralPath $summary -PathType Leaf) | Should -Be $true
        (Test-Path -LiteralPath $manifest -PathType Leaf) | Should -Be $true
        $value = Get-Content -LiteralPath $summary -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64 -DateKind String
        $value.schemaVersion | Should -Be 2
        $value.status | Should -Be 'PASS'
        $value.candidate.executable.sha256 | Should -Be $fixture.ExeSha
        $value.candidate.ffprobe.sha256 | Should -Be (Get-TestSha256 $fixture.Candidate.Ffprobe)
        $value.candidate.manifest.sha256 | Should -Be (Get-TestSha256 $fixture.Candidate.Manifest)
        @($value.cases).Count | Should -Be 6
        @($value.generatedProbes).Count | Should -Be 3

        $secondOutput = Join-Path $fixture.Root 'second-output'
        New-Item -ItemType Directory -Path $secondOutput | Out-Null
        (Invoke-GuiVerifier $fixture $secondOutput).ExitCode | Should -Be 0
        $secondFinal = Join-Path $secondOutput 'gui-validation-v2.19.1-karon.2'
        (Get-TestSha256 $summary) | Should -Be (Get-TestSha256 (Join-Path $secondFinal 'gui-validation-summary.json'))
        (Get-TestSha256 $manifest) | Should -Be (Get-TestSha256 (Join-Path $secondFinal 'gui-validation-evidence-manifest.json'))
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

    It 'rejects a uniform executable SHA that does not match candidate bytes' {
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

    It 'rejects a missing candidate ffprobe executable' {
        $fixture = New-ValidGuiFixture
        Remove-Item -LiteralPath $fixture.Candidate.Ffprobe
        Assert-VerifierRejects $fixture 'gui_candidate_ffprobe_missing'
    }

    It 'rejects candidate ffprobe bytes that do not match the supplied manifest' {
        $fixture = New-ValidGuiFixture
        $manifest = Get-Content -LiteralPath $fixture.Candidate.Manifest -Raw | ConvertFrom-Json -Depth 64 -DateKind String
        @($manifest.files | Where-Object { $_.path -ceq 'ffprobe.exe' })[0].sha256 = ('c' * 64)
        Write-TestJson $fixture.Candidate.Manifest $manifest
        Assert-VerifierRejects $fixture 'gui_candidate_manifest_mismatch: ffprobe.exe'
    }

    It 'rejects required video without audio' {
        $fixture = New-ValidGuiFixture
        Replace-LifecycleMedia $fixture 'ko-KR-100' $script:Media.VideoOnly
        Assert-VerifierRejects $fixture 'gui_ffprobe_audio_missing'
    }

    It 'rejects required video without video' {
        $fixture = New-ValidGuiFixture
        Replace-LifecycleMedia $fixture 'ko-KR-100' $script:Media.AudioOnly
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
        $case.Value.screenshots[0].width = 641
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

    It 'rejects an artifact length mismatch' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $case.Value.fullVideoLifecycle.output.length = [long]$case.Value.fullVideoLifecycle.output.length + 1
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_evidence_length_mismatch'
    }

    foreach ($checkName in @('mp3Conversion', 'settingsSaveRestartRestore', 'legacySettingsTransition')) {
        It "rejects missing representative coverage for $checkName" {
            $fixture = New-ValidGuiFixture
            $caseId = if ($checkName -ceq 'legacySettingsTransition') { 'en-US-200' } else { 'ko-KR-100' }
            $case = Read-TestCase $fixture $caseId
            $case.Value.representativeChecks.$checkName = $null
            Save-TestCase $case
            Assert-VerifierRejects $fixture "gui_representative_check_missing: $checkName"
        }
    }

    It 'rejects a false representative result' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $case.Value.representativeChecks.mp3Conversion.result = $false
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_representative_check_failed'
    }

    It 'rejects a plain secret-like query URL' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $case.Value.notes = 'https://media.example.invalid/file?signature=secret&expires=9999999999'
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_secret_material_detected'
    }

    It 'rejects a non-media file presented as required video' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.fullVideoLifecycle.output.path).Replace('/', '\'))
        [IO.File]::WriteAllText($path, 'not a video')
        Update-DescriptorForFile $case.Value.fullVideoLifecycle.output $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_ffprobe_failed|gui_ffprobe_video_missing'
    }

    It 'rejects a non-media file presented as MP3 output' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.representativeChecks.mp3Conversion.output.path).Replace('/', '\'))
        [IO.File]::WriteAllText($path, 'not an mp3')
        Update-DescriptorForFile $case.Value.representativeChecks.mp3Conversion.output $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_ffprobe_failed|gui_mp3_audio_invalid'
    }

    It 'rejects a JSON-escaped secret URL after decoding strings' {
        $fixture = New-ValidGuiFixture
        $casePath = Join-Path $fixture.Cases 'ko-KR-150.json'
        $raw = [IO.File]::ReadAllText($casePath)
        $raw = $raw.Replace('"notes": ""', '"notes": "https:\/\/media.example.invalid\/file?opaque=value"')
        [IO.File]::WriteAllText($casePath, $raw, [Text.UTF8Encoding]::new($false))
        Assert-VerifierRejects $fixture 'gui_secret_material_detected'
    }

    It 'rejects every unreferenced evidence file including binary data' {
        $fixture = New-ValidGuiFixture
        [IO.File]::WriteAllBytes((Join-Path $fixture.Evidence 'secret.bin'), [byte[]](1, 2, 3, 4))
        Assert-VerifierRejects $fixture 'gui_unreferenced_evidence_file'
    }

    It 'rejects a 24-byte PNG header without a decodable image body' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        [IO.File]::WriteAllBytes($path, [byte[]](137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,2,128,0,0,1,224))
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        $case.Value.screenshots[0].width = 640
        $case.Value.screenshots[0].height = 480
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_decode_failed'
    }

    It 'rejects a fully decodable but impractical 1x1 screenshot' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        Copy-Item -LiteralPath $script:Media.SmallPng -Destination $path -Force
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        $case.Value.screenshots[0].width = 1
        $case.Value.screenshots[0].height = 1
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_too_small'
    }

    It 'rejects evidence reached through a parent junction' {
        $fixture = New-ValidGuiFixture
        $junctionParent = Join-Path $fixture.Root 'junction-parent'
        $junction = Join-Path $junctionParent 'alias'
        New-Item -ItemType Directory -Path $junctionParent | Out-Null
        New-Item -ItemType Junction -Path $junction -Target $fixture.Root | Out-Null
        $fixture.Evidence = Join-Path $junction 'evidence'
        Assert-VerifierRejects $fixture 'gui_path_reparse_point'
    }

    It 'rejects unknown schema fields that could misdirect executable lookup' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $case.Value.executable | Add-Member -NotePropertyName path -NotePropertyValue 'other.exe'
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_schema_unknown_property'
    }

    It 'preserves another producer final directory during no-overwrite race' {
        $fixture = New-ValidGuiFixture
        $seedOutput = Join-Path $fixture.Root 'seed-output'
        New-Item -ItemType Directory -Path $seedOutput | Out-Null
        (Invoke-GuiVerifier $fixture $seedOutput).ExitCode | Should -Be 0
        $seedFinal = Join-Path $seedOutput 'gui-validation-v2.19.1-karon.2'
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
        $watcher.ExitCode | Should -Be 0
        $raceResult.ExitCode | Should -Not -Be 0
        $raceResult.Combined | Should -Match 'gui_validation_output_race'
        (Get-TestSha256 (Join-Path $raceFinal 'gui-validation-summary.json')) | Should -Be (Get-TestSha256 (Join-Path $seedFinal 'gui-validation-summary.json'))
        (Get-TestSha256 (Join-Path $raceFinal 'gui-validation-evidence-manifest.json')) | Should -Be (Get-TestSha256 (Join-Path $seedFinal 'gui-validation-evidence-manifest.json'))
        @(Get-ChildItem -LiteralPath $raceOutput -Directory -Filter '.gui-validation-v2.19.1-karon.2.partial.*').Count | Should -Be 0
    }

    It 'rejects a candidate executable changed after its initial hash' {
        $fixture = New-ValidGuiFixture
        $watcher = Start-TestInputMutation $fixture.Output $fixture.Exe 'AppendText'
        $result = Invoke-GuiVerifier $fixture
        $watcher.WaitForExit()
        $watcher.ExitCode | Should -Be 0
        $result.ExitCode | Should -Not -Be 0
        $result.Combined | Should -Match 'gui_input_changed'
    }

    It 'rejects a candidate manifest changed after its initial hash' {
        $fixture = New-ValidGuiFixture
        $watcher = Start-TestInputMutation $fixture.Output $fixture.Candidate.Manifest 'AppendText'
        $result = Invoke-GuiVerifier $fixture
        $watcher.WaitForExit()
        $watcher.ExitCode | Should -Be 0
        $result.ExitCode | Should -Not -Be 0
        $result.Combined | Should -Match 'gui_input_changed'
    }

    It 'rejects an evidence file added after the allowlist scan' {
        $fixture = New-ValidGuiFixture
        $secret = Join-Path $fixture.Evidence 'secret.bin'
        $watcher = Start-TestInputMutation $fixture.Output $secret 'CreateBinary'
        $result = Invoke-GuiVerifier $fixture
        $watcher.WaitForExit()
        $watcher.ExitCode | Should -Be 0
        $result.ExitCode | Should -Not -Be 0
        $result.Combined | Should -Match 'gui_input_changed'
    }

    It 'rejects PNG bytes appended after the terminal IEND chunk' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        [IO.File]::AppendAllText($path, 'polyglot-tail', [Text.UTF8Encoding]::new($false))
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_png_trailing_data'
    }

    It 'rejects a PNG ancillary chunk with an invalid CRC' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        $chunk = New-TestPngChunk 'tEXt' ([byte[]](97, 0, 98)) ([byte[]](0, 0, 0, 0))
        Add-TestPngChunkBeforeIend $path $chunk
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_png_crc_invalid'
    }

    It 'rejects a duplicate forbidden PNG critical chunk' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        $bytes = [IO.File]::ReadAllBytes($path)
        $duplicateIhdr = [byte[]]::new(25)
        [Buffer]::BlockCopy($bytes, 8, $duplicateIhdr, 0, 25)
        Add-TestPngChunkBeforeIend $path $duplicateIhdr
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_png_structure_invalid'
    }

    It 'rejects a valid PNG tEXt chunk containing a signed URL' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        $text = [Text.Encoding]::UTF8.GetBytes("Comment`0https://media.example.invalid/file?signature=secret")
        Add-TestPngChunkBeforeIend $path (New-ValidTestPngChunk 'tEXt' $text)
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_png_chunk_not_allowed'
    }

    It 'rejects NFC and NFD evidence names before case-folded uniqueness checks' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $oldRelative = [string]$case.Value.screenshots[0].path
        $oldPath = Join-Path $fixture.Evidence ($oldRelative.Replace('/', '\'))
        $nfcRelative = 'screenshots/ko-KR-150-' + [char]0x00e9 + '.png'
        $nfdRelative = 'screenshots/ko-KR-150-e' + [char]0x0301 + '.png'
        $nfcPath = Join-Path $fixture.Evidence ($nfcRelative.Replace('/', '\'))
        $nfdPath = Join-Path $fixture.Evidence ($nfdRelative.Replace('/', '\'))
        Move-Item -LiteralPath $oldPath -Destination $nfcPath
        Copy-Item -LiteralPath $nfcPath -Destination $nfdPath
        $first = $case.Value.screenshots[0]
        $first.path = $nfcRelative
        Update-DescriptorForFile $first $nfcPath
        $second = ($first | ConvertTo-Json -Depth 16) | ConvertFrom-Json -Depth 16 -DateKind String
        $second.path = $nfdRelative
        Update-DescriptorForFile $second $nfdPath
        $case.Value.screenshots = @($first, $second)
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_evidence_path_not_nfc'
    }

    It 'rejects PLTE placed after the first IDAT chunk' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        Add-TestPngChunkBeforeIend $path (New-ValidTestPngChunk 'PLTE' ([byte[]](0, 0, 0)))
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_png_structure_invalid'
    }

    It 'rejects nonconsecutive IDAT chunks' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        $firstIdat = New-ValidTestPngChunk 'IDAT' ([byte[]]@())
        $physical = New-ValidTestPngChunk 'pHYs' ([byte[]](0, 0, 0, 1, 0, 0, 0, 1, 0))
        $secondIdat = New-ValidTestPngChunk 'IDAT' ([byte[]]@())
        $inserted = [byte[]]::new($firstIdat.Length + $physical.Length + $secondIdat.Length)
        [Buffer]::BlockCopy($firstIdat, 0, $inserted, 0, $firstIdat.Length)
        [Buffer]::BlockCopy($physical, 0, $inserted, $firstIdat.Length, $physical.Length)
        [Buffer]::BlockCopy($secondIdat, 0, $inserted, $firstIdat.Length + $physical.Length, $secondIdat.Length)
        Insert-TestBytes $path (Get-TestPngChunkOffset $path 'IDAT') $inserted
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_png_structure_invalid'
    }

    It 'rejects malformed tRNS data for <Name> before the first IDAT' -TestCases @(
        @{ Name = 'grayscale length 0'; ColorType = [byte]0; Transparency = [byte[]]@(); Palette = $null },
        @{ Name = 'grayscale length 1'; ColorType = [byte]0; Transparency = [byte[]]@(1); Palette = $null },
        @{ Name = 'grayscale length 3'; ColorType = [byte]0; Transparency = [byte[]]@(1, 2, 3); Palette = $null },
        @{ Name = 'truecolor length 5'; ColorType = [byte]2; Transparency = [byte[]]@(1, 2, 3, 4, 5); Palette = $null },
        @{ Name = 'truecolor length 7'; ColorType = [byte]2; Transparency = [byte[]]@(1, 2, 3, 4, 5, 6, 7); Palette = $null },
        @{ Name = 'indexed length 0'; ColorType = [byte]3; Transparency = [byte[]]@(); Palette = [byte[]]@(0, 0, 0, 255, 255, 255) },
        @{ Name = 'indexed longer than PLTE'; ColorType = [byte]3; Transparency = [byte[]]@(0, 1, 2); Palette = [byte[]]@(0, 0, 0, 255, 255, 255) },
        @{ Name = 'grayscale alpha'; ColorType = [byte]4; Transparency = [byte[]]@(0, 1); Palette = $null },
        @{ Name = 'truecolor alpha'; ColorType = [byte]6; Transparency = [byte[]]@(0, 1); Palette = $null }
    ) {
        param($Name, $ColorType, $Transparency, $Palette)
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        Add-TestPngTransparencyBeforeIdat $path $ColorType $Transparency $Palette
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_png_structure_invalid'
    }

    It 'rejects type-2 tRNS placed before an optional PLTE chunk' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        Set-TestPngColorType $path 2
        Insert-TestBytes $path (Get-TestPngChunkOffset $path 'IDAT') (New-ValidTestPngChunk 'tRNS' ([byte[]](0, 0, 0, 0, 0, 0)))
        Insert-TestBytes $path (Get-TestPngChunkOffset $path 'IDAT') (New-ValidTestPngChunk 'PLTE' ([byte[]](0, 0, 0)))
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_png_structure_invalid'
    }

    It 'accepts type-2 PLTE followed by tRNS before the first IDAT' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        Set-TestPngColorType $path 2
        Insert-TestBytes $path (Get-TestPngChunkOffset $path 'IDAT') (New-ValidTestPngChunk 'PLTE' ([byte[]](0, 0, 0)))
        Insert-TestBytes $path (Get-TestPngChunkOffset $path 'IDAT') (New-ValidTestPngChunk 'tRNS' ([byte[]](0, 0, 0, 0, 0, 0)))
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        (Invoke-GuiVerifier $fixture).ExitCode | Should -Be 0
    }

    It 'rejects duplicate type-2 tRNS chunks before the first IDAT' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        Set-TestPngColorType $path 2
        Insert-TestBytes $path (Get-TestPngChunkOffset $path 'IDAT') (New-ValidTestPngChunk 'tRNS' ([byte[]](0, 0, 0, 0, 0, 0)))
        Insert-TestBytes $path (Get-TestPngChunkOffset $path 'IDAT') (New-ValidTestPngChunk 'tRNS' ([byte[]](0, 0, 0, 0, 0, 0)))
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_png_structure_invalid'
    }

    It 'rejects a sparse screenshot above the encoded byte budget before whole-file allocation' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.SetLength(33554433) }
        finally { $stream.Dispose() }
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_resource_limit'
        $parserSource = Get-TestFunctionSource $script:Verifier 'Assert-PngByteStructure'
        $parserSource | Should -Not -Match '\[IO\.File\]::ReadAllBytes'
        $lengthIndex = $parserSource.IndexOf('$stream.Length', [StringComparison]::Ordinal)
        $allocationIndex = $parserSource.IndexOf('[byte[]]::new', [StringComparison]::Ordinal)
        ($lengthIndex -ge 0 -and $allocationIndex -gt $lengthIndex) | Should -Be $true
    }

    It 'rejects a screenshot dimension beyond the configured maximum before decode' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        Set-TestPngDimensions $path 8193 480
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_resource_limit'
    }

    It 'rejects a screenshot exceeding the total pixel budget before decode' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        Set-TestPngDimensions $path 4096 2049
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_resource_limit'
    }

    It 'rejects a declared cumulative IDAT budget overflow before decode' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $path = Join-Path $fixture.Evidence (([string]$case.Value.screenshots[0].path).Replace('/', '\'))
        $bytes = [IO.File]::ReadAllBytes($path)
        $idatOffset = Get-TestPngChunkOffset $path 'IDAT'
        $bytes[$idatOffset] = 2
        $bytes[$idatOffset + 1] = 0
        $bytes[$idatOffset + 2] = 0
        $bytes[$idatOffset + 3] = 0
        [IO.File]::WriteAllBytes($path, $bytes[0..($idatOffset + 11)])
        Update-DescriptorForFile $case.Value.screenshots[0] $path
        Save-TestCase $case
        Assert-VerifierRejects $fixture 'gui_screenshot_resource_limit'
    }

    It 'accepts a canonical unique screenshot with an uppercase PNG extension' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-150'
        $oldRelative = [string]$case.Value.screenshots[0].path
        $oldPath = Join-Path $fixture.Evidence ($oldRelative.Replace('/', '\'))
        $temporaryPath = $oldPath + '.rename'
        $newRelative = $oldRelative.Substring(0, $oldRelative.Length - 4) + '.PNG'
        $newPath = Join-Path $fixture.Evidence ($newRelative.Replace('/', '\'))
        Move-Item -LiteralPath $oldPath -Destination $temporaryPath
        Move-Item -LiteralPath $temporaryPath -Destination $newPath
        $case.Value.screenshots[0].path = $newRelative
        Update-DescriptorForFile $case.Value.screenshots[0] $newPath
        Save-TestCase $case
        (Invoke-GuiVerifier $fixture).ExitCode | Should -Be 0
    }

    It 'rejects recorder case identifiers outside the exact fixed matrix' {
        $fixture = New-ValidGuiFixture
        $casePath = Join-Path $fixture.Cases 'ko-KR-100.json'
        $originalText = Get-Content -LiteralPath $casePath -Raw -Encoding UTF8
        foreach ($invalidId in @('../escape', 'ko-KR-100/child', 'C:stream', '.', '/rooted', '\\server\share\case', '\\?\C:\case')) {
            $case = $originalText | ConvertFrom-Json -Depth 64 -DateKind String
            $case.caseId = $invalidId
            Write-TestJson $casePath $case
            $result = Invoke-TestScript $script:Recorder @('-Action', 'Finalize', '-CasePath', $casePath)
            $result.ExitCode | Should -Not -Be 0
            $result.Combined | Should -Match 'operator_case_id_invalid'
        }
    }

    It 'rejects a recorder case whose fixed ID does not match its canonical filename' {
        $fixture = New-ValidGuiFixture
        $case = Read-TestCase $fixture 'ko-KR-100'
        $case.Value.caseId = 'en-US-100'
        Save-TestCase $case
        $result = Invoke-TestScript $script:Recorder @('-Action', 'Finalize', '-CasePath', $case.Path)
        $result.ExitCode | Should -Not -Be 0
        $result.Combined | Should -Match 'operator_case_path_invalid'
    }

    It 'rejects recorder evidence reached through a parent junction' {
        $fixture = New-ValidGuiFixture
        $junction = Join-Path $fixture.Root 'operator-junction'
        New-Item -ItemType Junction -Path $junction -Target $fixture.Evidence | Out-Null
        $casePath = Join-Path $junction 'cases\ko-KR-100.json'
        $result = Invoke-TestScript $script:Recorder @('-Action', 'Finalize', '-CasePath', $casePath)
        $result.ExitCode | Should -Not -Be 0
        $result.Combined | Should -Match 'operator_path_reparse_point'
    }

    It 'rejects device and UNC style input paths for local immutable evidence' {
        $fixture = New-ValidGuiFixture
        $deviceExe = '\\?\' + $fixture.Exe
        $result = Invoke-TestScript $script:Verifier @(
            '-EvidenceRoot', $fixture.Evidence,
            '-CandidateExePath', $deviceExe,
            '-OutputDirectory', $fixture.Output,
            '-MaximumEvidenceAgeHours', '24'
        )
        $result.ExitCode | Should -Not -Be 0
        $result.Combined | Should -Match 'gui_remote_path_not_allowed'
    }

    It 'emits the exact packaging consumer summary schema documented by the producer' {
        $fixture = New-ValidGuiFixture
        $result = Invoke-GuiVerifier $fixture
        $result.ExitCode | Should -Be 0
        $final = Join-Path $fixture.Output 'gui-validation-v2.19.1-karon.2'
        $summaryPath = Join-Path $final 'gui-validation-summary.json'
        $manifestPath = Join-Path $final 'gui-validation-evidence-manifest.json'
        $summaryText = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8
        $manifestText = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        $summary = $summaryText | ConvertFrom-Json -Depth 64 -DateKind String
        ($summary.PSObject.Properties.Name -join ',') | Should -Be 'schemaVersion,releaseVersion,status,candidate,cases,fullVideoLifecycleCases,representativeChecks,generatedProbes,evidenceFileCount,evidenceManifestFile'
        ($summary.representativeChecks.PSObject.Properties.Name -join ',') | Should -Be 'mp3Conversion,settingsSaveRestartRestore,legacySettingsTransition'
        ($summary.cases[0].PSObject.Properties.Name -join ',') | Should -Be 'caseId,language,dpi,evidenceFile,evidenceSha256'
        ($summary.generatedProbes[0].PSObject.Properties.Name -join ',') | Should -Be 'caseId,kind,sourceEvidencePath,path,sha256,length'
        $repoRoot = Split-Path -Parent (Split-Path -Parent $script:Verifier)
        $schemaPath = Join-Path $repoRoot 'release\validation\v2.19.1-karon.2\gui-validation-output.schema.json'
        (Test-Path -LiteralPath $schemaPath -PathType Leaf) | Should -Be $true
        ($summaryText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue) | Should -Be $true
        ($manifestText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue) | Should -Be $true
        $invalidSummary = $summaryText | ConvertFrom-Json -Depth 64 -DateKind String
        $invalidSummary | Add-Member -NotePropertyName ignoredExecutablePath -NotePropertyValue 'other.exe'
        (($invalidSummary | ConvertTo-Json -Depth 64) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue) | Should -Be $false
        $wrongVersion = $summaryText | ConvertFrom-Json -Depth 64 -DateKind String
        $wrongVersion.schemaVersion = '2'
        (($wrongVersion | ConvertTo-Json -Depth 64) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue) | Should -Be $false
        $readme = Get-Content -LiteralPath (Join-Path $repoRoot 'release\validation\v2.19.1-karon.2\README.md') -Raw -Encoding UTF8
        $readme | Should -Match ([regex]::Escape('gui-validation-output.schema.json'))
        $readme | Should -Match 'canonical machine-readable contract'
    }

    It 'pins the canonical producer schema path identity and root definitions' {
        $relativePath = 'release/validation/v2.19.1-karon.2/gui-validation-output.schema.json'
        $schemaPath = Join-Path $script:RepositoryRoot ($relativePath.Replace('/', '\'))
        (Test-Path -LiteralPath $schemaPath -PathType Leaf) | Should -Be $true
        ([IO.Path]::GetRelativePath($script:RepositoryRoot, (Resolve-Path $schemaPath).Path).Replace('\', '/')) | Should -Be $relativePath
        (Get-TestSha256 $schemaPath) | Should -Be 'e49cc70253bd5dd4b4abd8ee00406f5dd8ed39434e309e3e3c74694b85c1b80e'
        $schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
        $schema.'$id' | Should -Be 'https://github.com/KaronLabs/ytdlp-korean-interface/blob/v2.19.1-karon.2/release/validation/v2.19.1-karon.2/gui-validation-output.schema.json'
        (@($schema.oneOf | ForEach-Object { $_.'$ref' }) -join ',') | Should -Be '#/$defs/summary,#/$defs/evidenceManifest'
        ($schema.'$defs'.PSObject.Properties.Name -contains 'summary') | Should -Be $true
        ($schema.'$defs'.PSObject.Properties.Name -contains 'evidenceManifest') | Should -Be $true
    }

    It 'initializes operator case with no preset observations or environment PASS values' {
        $root = New-TestDirectory
        $evidence = Join-Path $root 'operator-evidence'
        $exe = Join-Path $root 'ytdlp-interface.exe'
        [IO.File]::WriteAllText($exe, 'operator-fixture')
        $result = Invoke-TestScript $script:Recorder @(
            '-Action', 'Initialize', '-EvidenceRoot', $evidence, '-CandidateExePath', $exe,
            '-Language', 'ko-KR', '-DpiPercent', '100'
        )
        $result.ExitCode | Should -Be 0
        $case = Get-Content -LiteralPath (Join-Path $evidence 'cases\ko-KR-100.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64 -DateKind String
        $case.schemaVersion | Should -Be 2
        $case.completedAtUtc | Should -Be $null
        $case.environment.observedLanguage | Should -Be $null
        $case.environment.observedDpiPercent | Should -Be $null
        foreach ($name in $script:ObservationNames) { $case.observations.$name | Should -Be $null }
        $case.representativeChecks.mp3Conversion | Should -Be $null
        $case.representativeChecks.settingsSaveRestartRestore | Should -Be $null
        $case.representativeChecks.legacySettingsTransition | Should -Be $null
    }
}
