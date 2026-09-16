#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $EvidenceRoot,
    [Parameter(Mandatory)] [string] $CandidateExePath,
    [Parameter(Mandatory)] [string] $OutputDirectory,
    [ValidateRange(1, 720)] [int] $MaximumEvidenceAgeHours = 168
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReleaseVersion = 'v2.19.1-karon.2'
$ExpectedCases = [ordered]@{
    'ko-KR-100' = [ordered]@{ language = 'ko-KR'; dpi = 100; lifecycle = $true }
    'ko-KR-150' = [ordered]@{ language = 'ko-KR'; dpi = 150; lifecycle = $false }
    'ko-KR-200' = [ordered]@{ language = 'ko-KR'; dpi = 200; lifecycle = $false }
    'en-US-100' = [ordered]@{ language = 'en-US'; dpi = 100; lifecycle = $false }
    'en-US-150' = [ordered]@{ language = 'en-US'; dpi = 150; lifecycle = $false }
    'en-US-200' = [ordered]@{ language = 'en-US'; dpi = 200; lifecycle = $true }
}
$ObservationNames = @(
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
$RepresentativeNames = @('mp3Conversion', 'settingsSaveRestartRestore', 'legacySettingsTransition')
$NowUtc = [DateTimeOffset]::UtcNow
$OldestUtc = $NowUtc.AddHours(-$MaximumEvidenceAgeHours)
$FutureLimitUtc = $NowUtc.AddMinutes(5)

function Test-Property {
    param([object] $Value, [string] $Name)
    $null -ne $Value -and $null -ne $Value.PSObject.Properties[$Name]
}

function Get-RequiredProperty {
    param([object] $Value, [string] $Name, [string] $ErrorId)
    if (-not (Test-Property $Value $Name)) { throw $ErrorId }
    $Value.PSObject.Properties[$Name].Value
}

function Assert-NoDuplicateJsonKeys {
    param([Text.Json.JsonElement] $Element)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'gui_json_duplicate_key' }
            Assert-NoDuplicateJsonKeys $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-NoDuplicateJsonKeys $item }
    }
}

function Assert-NoSecretMaterial {
    param([string] $Text)
    $patterns = @(
        '(?i)https?://[^\s"''<>]+\?[^\s"''<>]+',
        '(?i)\b(?:authorization|proxy-authorization|cookie|set-cookie)\s*[:=]',
        '(?i)\bbearer\s+[A-Za-z0-9._~+/-]{8,}',
        '(?i)\b(?:access|refresh|id|api)[_-]?token\s*[:=]',
        '(?i)(?:x-amz-|x-goog-|signature=|sig=|lsig=|credential=|key-pair-id=|policy=|token=|auth=|expires?=)',
        '\bgh[pousr]_[A-Za-z0-9]{20,}\b',
        '\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'
    )
    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) { throw 'gui_secret_material_detected' }
    }
}

function Read-StrictJson {
    param([string] $Path, [string] $ErrorId)
    try {
        $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
        Assert-NoSecretMaterial $text
        $document = [Text.Json.JsonDocument]::Parse($text)
        try { Assert-NoDuplicateJsonKeys $document.RootElement }
        finally { $document.Dispose() }
        ConvertFrom-Json -InputObject $text -Depth 64 -DateKind String
    }
    catch {
        if ($_.Exception.Message -match '^gui_(?:json_duplicate_key|secret_material_detected)$') { throw }
        throw $ErrorId
    }
}

function Get-Sha256 {
    param([string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-IntegerValue {
    param([object] $Value)
    $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

function ConvertFrom-EvidenceTimestamp {
    param([object] $Value, [string] $ErrorId)
    if ($Value -isnot [string]) { throw $ErrorId }
    $parsed = [DateTimeOffset]::MinValue
    $valid = [DateTimeOffset]::TryParseExact(
        $Value,
        "yyyy-MM-dd'T'HH:mm:ss.fff'Z'",
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
        [ref] $parsed
    )
    if (-not $valid) { throw $ErrorId }
    if ($parsed -lt $OldestUtc -or $parsed -gt $FutureLimitUtc) { throw 'gui_evidence_stale' }
    $parsed
}

function Assert-TimestampInCase {
    param([object] $Value, [DateTimeOffset] $Started, [DateTimeOffset] $Completed)
    $timestamp = ConvertFrom-EvidenceTimestamp $Value 'gui_timestamp_invalid'
    if ($timestamp -lt $Started -or $timestamp -gt $Completed) { throw 'gui_timestamp_outside_case' }
    $timestamp
}

function Resolve-EvidencePath {
    param([object] $RelativePath)
    if ($RelativePath -isnot [string] -or [string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath -match '[\\:\x00-\x1f<>"|?*]' -or $RelativePath.StartsWith('/')) {
        throw 'gui_evidence_path_invalid'
    }
    foreach ($part in $RelativePath.Split('/')) {
        if ($part -in @('', '.', '..') -or $part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') {
            throw 'gui_evidence_path_invalid'
        }
    }
    $root = [IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\', '/')
    $path = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'gui_evidence_path_invalid'
    }
    $path
}

function Assert-NoReparsePoint {
    param([string] $Path)
    $root = [IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\', '/')
    $current = [IO.Path]::GetFullPath($Path)
    while ($current.Length -ge $root.Length) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'gui_evidence_reparse_point' }
        if ($current.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { throw 'gui_evidence_path_invalid' }
        $current = $parent.FullName
    }
}

function Assert-EvidenceFile {
    param([object] $Descriptor)
    $relativePath = Get-RequiredProperty $Descriptor 'path' 'gui_evidence_descriptor_invalid'
    $expectedSha = Get-RequiredProperty $Descriptor 'sha256' 'gui_evidence_descriptor_invalid'
    $expectedLength = Get-RequiredProperty $Descriptor 'length' 'gui_evidence_descriptor_invalid'
    if ($expectedSha -isnot [string] -or $expectedSha -notmatch '^[a-fA-F0-9]{64}$') { throw 'gui_evidence_sha_invalid' }
    if (-not (Test-IntegerValue $expectedLength) -or [long]$expectedLength -le 0) { throw 'gui_evidence_length_invalid' }
    $path = Resolve-EvidencePath $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'gui_evidence_file_missing' }
    Assert-NoReparsePoint $path
    $item = Get-Item -LiteralPath $path
    if ($item.Length -ne [long]$expectedLength) { throw 'gui_evidence_length_mismatch' }
    $actualSha = Get-Sha256 $path
    if ($actualSha -cne $expectedSha.ToLowerInvariant()) { throw 'gui_evidence_hash_mismatch' }
    [pscustomobject]@{ RelativePath = [string]$relativePath; FullPath = $path; Sha256 = $actualSha; Length = $item.Length }
}

function Get-PngDimensions {
    param([string] $Path)
    $bytes = [byte[]]::new(24)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Read($bytes, 0, $bytes.Length) -ne $bytes.Length) { throw 'gui_screenshot_invalid_png' }
    }
    finally { $stream.Dispose() }
    $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
    for ($i = 0; $i -lt $signature.Length; $i++) {
        if ($bytes[$i] -ne $signature[$i]) { throw 'gui_screenshot_invalid_png' }
    }
    $width = ([uint32]$bytes[16] -shl 24) -bor ([uint32]$bytes[17] -shl 16) -bor ([uint32]$bytes[18] -shl 8) -bor [uint32]$bytes[19]
    $height = ([uint32]$bytes[20] -shl 24) -bor ([uint32]$bytes[21] -shl 16) -bor ([uint32]$bytes[22] -shl 8) -bor [uint32]$bytes[23]
    if ($width -eq 0 -or $height -eq 0) { throw 'gui_screenshot_invalid_png' }
    [pscustomobject]@{ Width = [int64]$width; Height = [int64]$height }
}

function Assert-BooleanTrue {
    param([object] $Value, [string] $NotBooleanError, [string] $FalseError)
    if ($Value -isnot [bool]) { throw $NotBooleanError }
    if (-not $Value) { throw $FalseError }
}

function Get-AllEvidenceFiles {
    $files = [Collections.Generic.List[object]]::new()
    foreach ($entry in Get-ChildItem -LiteralPath $EvidenceRoot -File -Recurse -Force) {
        Assert-NoReparsePoint $entry.FullName
        $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($EvidenceRoot), $entry.FullName).Replace('\', '/')
        if ($entry.Extension -in @('.json', '.txt', '.log', '.md', '.csv', '.xml', '.yaml', '.yml')) {
            $text = [IO.File]::ReadAllText($entry.FullName, [Text.UTF8Encoding]::new($false, $true))
            Assert-NoSecretMaterial $text
        }
        $files.Add([pscustomobject]@{ RelativePath = $relative; FullPath = $entry.FullName })
    }
    $files.Sort([Comparison[object]]{
        param($left, $right)
        [StringComparer]::Ordinal.Compare($left.RelativePath, $right.RelativePath)
    })
    $files
}

function ConvertTo-DeterministicJsonText {
    param([object] $Value)
    (($Value | ConvertTo-Json -Depth 64).Replace("`r`n", "`n") + "`n")
}

function Invoke-GuiEvidenceVerification {
    $evidenceFull = [IO.Path]::GetFullPath($EvidenceRoot)
    if (-not (Test-Path -LiteralPath $evidenceFull -PathType Container)) { throw 'gui_evidence_root_missing' }
    $script:EvidenceRoot = $evidenceFull
    Assert-NoReparsePoint $evidenceFull

    $exeFull = [IO.Path]::GetFullPath($CandidateExePath)
    if (-not (Test-Path -LiteralPath $exeFull -PathType Leaf) -or [IO.Path]::GetFileName($exeFull) -cne 'ytdlp-interface.exe') {
        throw 'gui_candidate_executable_invalid'
    }
    if (((Get-Item -LiteralPath $exeFull).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'gui_candidate_executable_reparse_point' }
    $actualExe = Get-Item -LiteralPath $exeFull
    $actualExeSha = Get-Sha256 $exeFull

    $outputFull = [IO.Path]::GetFullPath($OutputDirectory)
    if ($outputFull.StartsWith($evidenceFull.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'gui_output_inside_evidence_root'
    }
    if (-not (Test-Path -LiteralPath $outputFull)) { New-Item -ItemType Directory -Path $outputFull | Out-Null }
    if (-not (Test-Path -LiteralPath $outputFull -PathType Container)) { throw 'gui_output_directory_invalid' }

    $caseDirectory = Join-Path $evidenceFull 'cases'
    if (-not (Test-Path -LiteralPath $caseDirectory -PathType Container)) { throw 'gui_case_directory_missing' }
    $caseFiles = @(Get-ChildItem -LiteralPath $caseDirectory -File -Filter '*.json')
    if ($caseFiles.Count -ne $ExpectedCases.Count) { throw 'gui_case_count_invalid' }

    $caseRecords = [Collections.Generic.List[object]]::new()
    $casesById = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $casePaths = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $exeHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in $caseFiles) {
        Assert-NoReparsePoint $file.FullName
        $case = Read-StrictJson $file.FullName 'gui_case_json_invalid'
        $caseId = Get-RequiredProperty $case 'caseId' 'gui_case_id_missing'
        if ($caseId -isnot [string]) { throw 'gui_case_id_invalid' }
        $caseRecords.Add([pscustomobject]@{ CaseId = $caseId; Case = $case; File = $file })
        $executable = Get-RequiredProperty $case 'executable' 'gui_executable_missing'
        $sha = Get-RequiredProperty $executable 'sha256' 'gui_executable_sha_missing'
        if ($sha -isnot [string] -or $sha -notmatch '^[a-fA-F0-9]{64}$') { throw 'gui_executable_sha_invalid' }
        $null = $exeHashes.Add($sha.ToLowerInvariant())
    }

    foreach ($record in $caseRecords) {
        if (-not $casesById.TryAdd($record.CaseId, $record.Case)) { throw 'gui_case_duplicate' }
        $casePaths.Add($record.CaseId, [IO.Path]::GetRelativePath($evidenceFull, $record.File.FullName).Replace('\', '/'))
    }
    foreach ($record in $caseRecords) {
        if ($record.File.BaseName -cne $record.CaseId) { throw 'gui_case_filename_mismatch' }
    }

    if ($exeHashes.Count -ne 1) { throw 'gui_executable_sha_mixed' }
    $recordedExeSha = @($exeHashes)[0]
    if ($recordedExeSha -cne $actualExeSha) { throw 'gui_executable_hash_mismatch' }

    foreach ($expectedId in $ExpectedCases.Keys) {
        if (-not $casesById.ContainsKey($expectedId)) { throw 'gui_case_set_invalid' }
    }

    $seenScreenshotPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $representativeCoverage = [ordered]@{
        mp3Conversion = [Collections.Generic.List[string]]::new()
        settingsSaveRestartRestore = [Collections.Generic.List[string]]::new()
        legacySettingsTransition = [Collections.Generic.List[string]]::new()
    }

    foreach ($caseId in $ExpectedCases.Keys) {
        $definition = $ExpectedCases[$caseId]
        $case = $casesById[$caseId]
        if ((Get-RequiredProperty $case 'schemaVersion' 'gui_schema_version_missing') -cne 1) { throw 'gui_schema_version_invalid' }
        if ((Get-RequiredProperty $case 'releaseVersion' 'gui_release_version_missing') -cne $ReleaseVersion) { throw 'gui_release_version_invalid' }
        if ((Get-RequiredProperty $case 'language' 'gui_language_missing') -cne $definition.language) { throw 'gui_language_mismatch' }
        $dpi = Get-RequiredProperty $case 'dpiPercent' 'gui_dpi_missing'
        if (-not (Test-IntegerValue $dpi) -or [int]$dpi -ne $definition.dpi) { throw 'gui_dpi_mismatch' }

        $started = ConvertFrom-EvidenceTimestamp (Get-RequiredProperty $case 'startedAtUtc' 'gui_started_timestamp_missing') 'gui_started_timestamp_invalid'
        $completed = ConvertFrom-EvidenceTimestamp (Get-RequiredProperty $case 'completedAtUtc' 'gui_completed_timestamp_missing') 'gui_completed_timestamp_invalid'
        if ($completed -lt $started) { throw 'gui_case_interval_invalid' }

        $executable = $case.executable
        if ((Get-RequiredProperty $executable 'fileName' 'gui_executable_filename_missing') -cne 'ytdlp-interface.exe') { throw 'gui_executable_filename_invalid' }
        $recordedLength = Get-RequiredProperty $executable 'length' 'gui_executable_length_missing'
        if (-not (Test-IntegerValue $recordedLength) -or [long]$recordedLength -ne $actualExe.Length) { throw 'gui_executable_length_mismatch' }

        $environment = Get-RequiredProperty $case 'environment' 'gui_environment_missing'
        if ((Get-RequiredProperty $environment 'observedLanguage' 'gui_observed_language_missing') -cne $definition.language) { throw 'gui_language_mismatch' }
        $observedDpi = Get-RequiredProperty $environment 'observedDpiPercent' 'gui_observed_dpi_missing'
        if (-not (Test-IntegerValue $observedDpi) -or [int]$observedDpi -ne $definition.dpi) { throw 'gui_dpi_mismatch' }
        $null = Assert-TimestampInCase (Get-RequiredProperty $environment 'recordedAtUtc' 'gui_environment_timestamp_missing') $started $completed

        $observations = Get-RequiredProperty $case 'observations' 'gui_observations_missing'
        foreach ($observationName in $ObservationNames) {
            $observation = Get-RequiredProperty $observations $observationName "gui_observation_missing: $observationName"
            if ($null -eq $observation) { throw "gui_observation_missing: $observationName" }
            $result = Get-RequiredProperty $observation 'result' "gui_observation_result_missing: $observationName"
            if ($result -isnot [bool]) { throw "gui_observation_not_boolean: $observationName" }
            if (-not $result) {
                if ($observationName -ceq 'noClipping') { throw 'gui_clipping_detected' }
                throw "gui_observation_failed: $observationName"
            }
            $null = Assert-TimestampInCase (Get-RequiredProperty $observation 'observedAtUtc' "gui_observation_timestamp_missing: $observationName") $started $completed
        }

        $screenshots = @(Get-RequiredProperty $case 'screenshots' 'gui_screenshots_missing')
        if ($screenshots.Count -eq 0) { throw 'gui_screenshots_missing' }
        $caseScreenshotPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($screenshot in $screenshots) {
            $file = Assert-EvidenceFile $screenshot
            if ([IO.Path]::GetExtension($file.RelativePath) -cne '.png') { throw 'gui_screenshot_not_png' }
            if (-not $seenScreenshotPaths.Add($file.RelativePath)) { throw 'gui_screenshot_reused_between_cases' }
            $null = $caseScreenshotPaths.Add($file.RelativePath)
            $dimensions = Get-PngDimensions $file.FullPath
            $width = Get-RequiredProperty $screenshot 'width' 'gui_screenshot_width_missing'
            $height = Get-RequiredProperty $screenshot 'height' 'gui_screenshot_height_missing'
            if (-not (Test-IntegerValue $width) -or -not (Test-IntegerValue $height) -or
                [int64]$width -ne $dimensions.Width -or [int64]$height -ne $dimensions.Height) {
                throw 'gui_screenshot_dimensions_mismatch'
            }
            $null = Assert-TimestampInCase (Get-RequiredProperty $screenshot 'capturedAtUtc' 'gui_screenshot_timestamp_missing') $started $completed
        }

        $lifecycle = Get-RequiredProperty $case 'fullVideoLifecycle' 'gui_lifecycle_property_missing'
        if ($definition.lifecycle -and $null -eq $lifecycle) { throw 'gui_lifecycle_missing' }
        if ($null -ne $lifecycle) {
            Assert-BooleanTrue (Get-RequiredProperty $lifecycle 'completed' 'gui_lifecycle_completion_missing') 'gui_lifecycle_not_boolean' 'gui_lifecycle_failed'
            $null = Assert-TimestampInCase (Get-RequiredProperty $lifecycle 'observedAtUtc' 'gui_lifecycle_timestamp_missing') $started $completed
            $expectedWidth = Get-RequiredProperty $lifecycle 'expectedWidth' 'gui_lifecycle_width_missing'
            $expectedHeight = Get-RequiredProperty $lifecycle 'expectedHeight' 'gui_lifecycle_height_missing'
            if (-not (Test-IntegerValue $expectedWidth) -or -not (Test-IntegerValue $expectedHeight) -or
                [int]$expectedWidth -le 0 -or [int]$expectedHeight -le 0 -or
                [Math]::Min([int]$expectedWidth, [int]$expectedHeight) -ne 1080) {
                throw 'gui_lifecycle_expected_resolution_invalid'
            }
            $null = Assert-EvidenceFile (Get-RequiredProperty $lifecycle 'output' 'gui_lifecycle_output_missing')
            $probeFile = Assert-EvidenceFile (Get-RequiredProperty $lifecycle 'ffprobe' 'gui_lifecycle_ffprobe_missing')
            $probe = Read-StrictJson $probeFile.FullPath 'gui_ffprobe_json_invalid'
            $streams = @(Get-RequiredProperty $probe 'streams' 'gui_ffprobe_streams_missing')
            $videoStreams = @($streams | Where-Object { (Test-Property $_ 'codec_type') -and $_.codec_type -ceq 'video' })
            $audioStreams = @($streams | Where-Object { (Test-Property $_ 'codec_type') -and $_.codec_type -ceq 'audio' })
            if ($videoStreams.Count -eq 0) { throw 'gui_ffprobe_video_missing' }
            if ($audioStreams.Count -eq 0) { throw 'gui_ffprobe_audio_missing' }
            $matchingVideo = @($videoStreams | Where-Object {
                (Test-Property $_ 'width') -and (Test-Property $_ 'height') -and
                (Test-IntegerValue $_.width) -and (Test-IntegerValue $_.height) -and
                [int]$_.width -eq [int]$expectedWidth -and [int]$_.height -eq [int]$expectedHeight
            })
            if ($matchingVideo.Count -eq 0) { throw 'gui_ffprobe_resolution_mismatch' }
        }

        $representatives = Get-RequiredProperty $case 'representativeChecks' 'gui_representative_checks_missing'
        foreach ($checkName in $RepresentativeNames) {
            $check = Get-RequiredProperty $representatives $checkName "gui_representative_property_missing: $checkName"
            if ($null -eq $check) { continue }
            $result = Get-RequiredProperty $check 'result' "gui_representative_result_missing: $checkName"
            if ($result -isnot [bool]) { throw "gui_representative_check_not_boolean: $checkName" }
            if (-not $result) { throw "gui_representative_check_failed: $checkName" }
            $null = Assert-TimestampInCase (Get-RequiredProperty $check 'observedAtUtc' "gui_representative_timestamp_missing: $checkName") $started $completed
            if ($checkName -ceq 'mp3Conversion') {
                $mp3 = Assert-EvidenceFile (Get-RequiredProperty $check 'output' 'gui_mp3_output_missing')
                if ([IO.Path]::GetExtension($mp3.RelativePath) -cne '.mp3') { throw 'gui_mp3_output_invalid' }
            }
            else {
                $screenshotPath = Get-RequiredProperty $check 'screenshotPath' "gui_representative_screenshot_missing: $checkName"
                if ($screenshotPath -isnot [string] -or -not $caseScreenshotPaths.Contains($screenshotPath)) {
                    throw "gui_representative_screenshot_invalid: $checkName"
                }
            }
            $representativeCoverage[$checkName].Add($caseId)
        }
    }

    foreach ($checkName in $RepresentativeNames) {
        if ($representativeCoverage[$checkName].Count -eq 0) { throw "gui_representative_check_missing: $checkName" }
    }

    $finalName = 'gui-validation-v2.19.1-karon.2'
    $finalPath = Join-Path $outputFull $finalName
    if (Test-Path -LiteralPath $finalPath) { throw 'gui_validation_output_exists' }
    $partialPath = Join-Path $outputFull ('.' + $finalName + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $partialPath | Out-Null
    try {
        $evidenceFiles = Get-AllEvidenceFiles
        $manifestFiles = [Collections.Generic.List[object]]::new()
        foreach ($file in $evidenceFiles) {
            $item = Get-Item -LiteralPath $file.FullPath
            $manifestFiles.Add([ordered]@{
                path = $file.RelativePath
                sha256 = Get-Sha256 $file.FullPath
                length = $item.Length
            })
        }

        $summary = [ordered]@{
            schemaVersion = 1
            releaseVersion = $ReleaseVersion
            status = 'PASS'
            executableSha256 = $actualExeSha
            executableLength = $actualExe.Length
            cases = @($ExpectedCases.Keys)
            fullVideoLifecycleCases = @('ko-KR-100', 'en-US-200')
            representativeChecks = [ordered]@{
                mp3Conversion = @($representativeCoverage.mp3Conversion)
                settingsSaveRestartRestore = @($representativeCoverage.settingsSaveRestartRestore)
                legacySettingsTransition = @($representativeCoverage.legacySettingsTransition)
            }
            evidenceFileCount = $manifestFiles.Count
            evidenceManifestFile = 'gui-validation-evidence-manifest.json'
        }
        $manifest = [ordered]@{
            schemaVersion = 1
            releaseVersion = $ReleaseVersion
            executable = [ordered]@{ fileName = 'ytdlp-interface.exe'; sha256 = $actualExeSha; length = $actualExe.Length }
            files = @($manifestFiles)
        }
        [IO.File]::WriteAllText((Join-Path $partialPath 'gui-validation-summary.json'), (ConvertTo-DeterministicJsonText $summary), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $partialPath 'gui-validation-evidence-manifest.json'), (ConvertTo-DeterministicJsonText $manifest), [Text.UTF8Encoding]::new($false))
        try { [IO.Directory]::Move($partialPath, $finalPath) }
        catch { throw [InvalidOperationException]::new('gui_validation_output_race', $_.Exception) }
    }
    finally {
        if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Recurse -Force }
    }

    Write-Host "PASS: GUI release evidence sealed at $finalPath"
}

try {
    Invoke-GuiEvidenceVerification
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
