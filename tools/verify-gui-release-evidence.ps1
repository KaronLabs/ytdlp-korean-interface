#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $EvidenceRoot,
    [Parameter(Mandatory)] [string] $CandidateExePath,
    [string] $CandidateManifestPath,
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

function Assert-ExactProperties {
    param([object] $Value, [string[]] $Names)
    if ($null -eq $Value -or $Value -isnot [pscustomobject]) { throw 'gui_schema_object_required' }
    $allowed = [Collections.Generic.HashSet[string]]::new($Names, [StringComparer]::Ordinal)
    $actual = @($Value.PSObject.Properties.Name)
    foreach ($name in $actual) {
        if (-not $allowed.Contains($name)) { throw "gui_schema_unknown_property: $name" }
    }
    foreach ($name in $Names) {
        if ($name -notin $actual) { throw "gui_schema_missing_property: $name" }
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

function Assert-JsonElementSafe {
    param([Text.Json.JsonElement] $Element)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'gui_json_duplicate_key' }
            Assert-JsonElementSafe $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-JsonElementSafe $item }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::String) {
        Assert-NoSecretMaterial $Element.GetString()
    }
}

function ConvertFrom-StrictJsonText {
    param([string] $Text, [string] $ErrorId)
    try {
        $document = [Text.Json.JsonDocument]::Parse($Text)
        try { Assert-JsonElementSafe $document.RootElement }
        finally { $document.Dispose() }
        ConvertFrom-Json -InputObject $Text -Depth 64 -DateKind String
    }
    catch {
        if ($_.Exception.Message -match '^gui_(?:json_duplicate_key|secret_material_detected)$') { throw }
        throw $ErrorId
    }
}

function Read-StrictJson {
    param([string] $Path, [string] $ErrorId)
    try {
        $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    }
    catch { throw $ErrorId }
    ConvertFrom-StrictJsonText $text $ErrorId
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

function Assert-NoReparseChain {
    param([string] $Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'gui_path_reparse_point' }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
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

function Register-EvidencePath {
    param([string] $RelativePath, [Collections.Generic.HashSet[string]] $Referenced)
    if (-not $Referenced.Add($RelativePath)) { throw "gui_evidence_file_reused: $RelativePath" }
}

function Assert-EvidenceFile {
    param([object] $Descriptor, [Collections.Generic.HashSet[string]] $Referenced)
    Assert-ExactProperties $Descriptor @('path', 'sha256', 'length')
    $relativePath = $Descriptor.path
    $expectedSha = $Descriptor.sha256
    $expectedLength = $Descriptor.length
    if ($expectedSha -isnot [string] -or $expectedSha -notmatch '^[a-fA-F0-9]{64}$') { throw 'gui_evidence_sha_invalid' }
    if (-not (Test-IntegerValue $expectedLength) -or [long]$expectedLength -le 0) { throw 'gui_evidence_length_invalid' }
    $path = Resolve-EvidencePath $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'gui_evidence_file_missing' }
    Assert-NoReparseChain $path
    $item = Get-Item -LiteralPath $path
    if ($item.Length -ne [long]$expectedLength) { throw 'gui_evidence_length_mismatch' }
    $actualSha = Get-Sha256 $path
    if ($actualSha -cne $expectedSha.ToLowerInvariant()) { throw 'gui_evidence_hash_mismatch' }
    Register-EvidencePath $relativePath $Referenced
    [pscustomobject]@{ RelativePath = [string]$relativePath; FullPath = $path; Sha256 = $actualSha; Length = $item.Length }
}

function Get-DecodedPngDimensions {
    param([string] $Path)
    try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }
    catch { throw 'gui_image_decoder_unavailable' }
    $stream = $null
    $image = $null
    $bitmap = $null
    $data = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $image = [Drawing.Image]::FromStream($stream, $true, $true)
        if ($image.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid) { throw 'gui_screenshot_decode_failed' }
        $bitmap = [Drawing.Bitmap]::new($image)
        $rectangle = [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height)
        $data = $bitmap.LockBits($rectangle, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bitmap.UnlockBits($data)
        $data = $null
        [pscustomobject]@{ Width = [int64]$bitmap.Width; Height = [int64]$bitmap.Height }
    }
    catch {
        if ($null -ne $data -and $null -ne $bitmap) { try { $bitmap.UnlockBits($data) } catch {} }
        if ($_.Exception.Message -match '^gui_') { throw }
        throw 'gui_screenshot_decode_failed'
    }
    finally {
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $image) { $image.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Assert-BooleanTrue {
    param([object] $Value, [string] $NotBooleanError, [string] $FalseError)
    if ($Value -isnot [bool]) { throw $NotBooleanError }
    if (-not $Value) { throw $FalseError }
}

function Get-CandidateBinding {
    param([string] $ExePath, [string] $ManifestPath)
    $exe = [IO.Path]::GetFullPath($ExePath)
    Assert-NoReparseChain $exe
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or [IO.Path]::GetFileName($exe) -cne 'ytdlp-interface.exe') {
        throw 'gui_candidate_executable_invalid'
    }
    $candidateDirectory = Split-Path -Parent $exe
    Assert-NoReparseChain $candidateDirectory
    $ffprobe = Join-Path $candidateDirectory 'ffprobe.exe'
    Assert-NoReparseChain $ffprobe
    if (-not (Test-Path -LiteralPath $ffprobe -PathType Leaf)) { throw 'gui_candidate_ffprobe_missing' }

    $exeItem = Get-Item -LiteralPath $exe
    $ffprobeItem = Get-Item -LiteralPath $ffprobe
    if ($exeItem.Length -le 0 -or $ffprobeItem.Length -le 0) { throw 'gui_candidate_file_invalid' }
    $binding = [ordered]@{
        executable = [ordered]@{ fileName = 'ytdlp-interface.exe'; sha256 = Get-Sha256 $exe; length = $exeItem.Length }
        ffprobe = [ordered]@{ fileName = 'ffprobe.exe'; sha256 = Get-Sha256 $ffprobe; length = $ffprobeItem.Length }
        manifest = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
        $manifest = [IO.Path]::GetFullPath($ManifestPath)
        Assert-NoReparseChain $manifest
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf) -or
            [IO.Path]::GetFileName($manifest) -cne 'candidate-manifest.json' -or
            -not (Split-Path -Parent $manifest).Equals($candidateDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'gui_candidate_manifest_invalid'
        }
        $value = Read-StrictJson $manifest 'gui_candidate_manifest_invalid'
        Assert-ExactProperties $value @('schemaVersion', 'createdAtUtc', 'attestation', 'versions', 'files')
        if ($value.schemaVersion -cne 1 -or $value.files -isnot [Array]) { throw 'gui_candidate_manifest_invalid' }
        $entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in @($value.files)) {
            Assert-ExactProperties $entry @('path', 'sha256', 'length')
            if ($entry.path -isnot [string] -or -not $entries.TryAdd($entry.path, $entry)) { throw 'gui_candidate_manifest_invalid' }
        }
        foreach ($required in @('ytdlp-interface.exe', 'ffprobe.exe')) {
            if (-not $entries.ContainsKey($required)) { throw "gui_candidate_manifest_entry_missing: $required" }
            $entry = $entries[$required]
            $actual = if ($required -ceq 'ytdlp-interface.exe') { $binding.executable } else { $binding.ffprobe }
            if ($entry.sha256 -isnot [string] -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
                -not (Test-IntegerValue $entry.length) -or
                $entry.sha256.ToLowerInvariant() -cne $actual.sha256 -or [long]$entry.length -ne $actual.length) {
                throw "gui_candidate_manifest_mismatch: $required"
            }
        }
        $manifestItem = Get-Item -LiteralPath $manifest
        $binding.manifest = [ordered]@{ fileName = 'candidate-manifest.json'; sha256 = Get-Sha256 $manifest; length = $manifestItem.Length }
    }

    [pscustomobject]@{
        Directory = $candidateDirectory
        FfprobePath = $ffprobe
        Public = $binding
    }
}

function Invoke-SealedFfprobe {
    param([string] $FfprobePath, [string] $MediaPath)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FfprobePath
    $startInfo.WorkingDirectory = Split-Path -Parent $FfprobePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-v', 'error', '-show_streams', '-show_format', '-of', 'json', '-i', $MediaPath)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'gui_ffprobe_start_failed' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            try { $process.Kill($true) } catch {}
            throw 'gui_ffprobe_timeout'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
            throw "gui_ffprobe_failed: exit=$($process.ExitCode) $stderr"
        }
        ConvertFrom-StrictJsonText $stdout 'gui_ffprobe_json_invalid'
    }
    finally { $process.Dispose() }
}

function ConvertTo-CanonicalProbe {
    param([object] $Probe)
    $streams = @(Get-RequiredProperty $Probe 'streams' 'gui_ffprobe_streams_missing')
    $orderedStreams = @($streams | Sort-Object { if (Test-Property $_ 'index') { [int]$_.index } else { [int]::MaxValue } })
    $canonicalStreams = [Collections.Generic.List[object]]::new()
    foreach ($stream in $orderedStreams) {
        $entry = [ordered]@{
            index = if (Test-Property $stream 'index') { [int]$stream.index } else { -1 }
            codecType = if (Test-Property $stream 'codec_type') { [string]$stream.codec_type } else { '' }
            codecName = if (Test-Property $stream 'codec_name') { [string]$stream.codec_name } else { '' }
        }
        if ($entry.codecType -ceq 'video') {
            $entry.width = if (Test-Property $stream 'width') { [int]$stream.width } else { 0 }
            $entry.height = if (Test-Property $stream 'height') { [int]$stream.height } else { 0 }
        }
        elseif ($entry.codecType -ceq 'audio') {
            $entry.channels = if (Test-Property $stream 'channels') { [int]$stream.channels } else { 0 }
            $entry.sampleRate = if (Test-Property $stream 'sample_rate') { [string]$stream.sample_rate } else { '' }
        }
        $canonicalStreams.Add($entry)
    }
    $format = Get-RequiredProperty $Probe 'format' 'gui_ffprobe_format_missing'
    [ordered]@{
        schemaVersion = 1
        streams = @($canonicalStreams)
        format = [ordered]@{
            formatName = if (Test-Property $format 'format_name') { [string]$format.format_name } else { '' }
            duration = if (Test-Property $format 'duration') { [string]$format.duration } else { '' }
            size = if (Test-Property $format 'size') { [string]$format.size } else { '' }
        }
    }
}

function Assert-ProbeMatchesRequest {
    param([object] $Probe, [object] $Request)
    $streams = @(Get-RequiredProperty $Probe 'streams' 'gui_ffprobe_streams_missing')
    $video = @($streams | Where-Object { (Test-Property $_ 'codec_type') -and $_.codec_type -ceq 'video' })
    $audio = @($streams | Where-Object { (Test-Property $_ 'codec_type') -and $_.codec_type -ceq 'audio' })
    if ($Request.Kind -ceq 'video') {
        if ($video.Count -eq 0) { throw 'gui_ffprobe_video_missing' }
        if ($audio.Count -eq 0) { throw 'gui_ffprobe_audio_missing' }
        $matching = @($video | Where-Object {
            (Test-Property $_ 'width') -and (Test-Property $_ 'height') -and
            (Test-IntegerValue $_.width) -and (Test-IntegerValue $_.height) -and
            [int]$_.width -eq $Request.ExpectedWidth -and [int]$_.height -eq $Request.ExpectedHeight
        })
        if ($matching.Count -eq 0) { throw 'gui_ffprobe_resolution_mismatch' }
        return
    }
    if ($video.Count -ne 0 -or $audio.Count -eq 0) { throw 'gui_mp3_audio_invalid' }
    $format = Get-RequiredProperty $Probe 'format' 'gui_ffprobe_format_missing'
    $formatName = if (Test-Property $format 'format_name') { [string]$format.format_name } else { '' }
    $mp3Audio = @($audio | Where-Object { (Test-Property $_ 'codec_name') -and $_.codec_name -ceq 'mp3' })
    if (($formatName.Split(',') -notcontains 'mp3') -or $mp3Audio.Count -eq 0) { throw 'gui_mp3_audio_invalid' }
}

function Assert-ExactEvidenceFileSet {
    param([Collections.Generic.HashSet[string]] $Referenced)
    $actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -Force) {
        Assert-NoReparseChain $entry.FullName
        if (-not $entry.PSIsContainer) {
            $relative = [IO.Path]::GetRelativePath($EvidenceRoot, $entry.FullName).Replace('\', '/')
            $null = $actual.Add($relative)
        }
    }
    foreach ($path in $actual) {
        if (-not $Referenced.Contains($path)) { throw "gui_unreferenced_evidence_file: $path" }
    }
    foreach ($path in $Referenced) {
        if (-not $actual.Contains($path)) { throw "gui_referenced_evidence_file_missing: $path" }
    }
    if ($actual.Count -ne $Referenced.Count) { throw 'gui_evidence_file_set_mismatch' }
}

function ConvertTo-DeterministicJsonText {
    param([object] $Value)
    (($Value | ConvertTo-Json -Depth 64).Replace("`r`n", "`n") + "`n")
}

function Get-InputEvidenceManifest {
    param([Collections.Generic.HashSet[string]] $Referenced)
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($path in $Referenced) { $paths.Add($path) }
    $paths.Sort([StringComparer]::Ordinal)
    $result = [Collections.Generic.List[object]]::new()
    foreach ($relative in $paths) {
        $full = Resolve-EvidencePath $relative
        $item = Get-Item -LiteralPath $full
        $result.Add([ordered]@{ path = $relative; sha256 = Get-Sha256 $full; length = $item.Length })
    }
    $result
}

function Invoke-GuiEvidenceVerification {
    $evidenceFull = [IO.Path]::GetFullPath($EvidenceRoot)
    Assert-NoReparseChain $evidenceFull
    if (-not (Test-Path -LiteralPath $evidenceFull -PathType Container)) { throw 'gui_evidence_root_missing' }
    $script:EvidenceRoot = $evidenceFull

    $candidate = Get-CandidateBinding $CandidateExePath $CandidateManifestPath
    $actualExe = $candidate.Public.executable

    $outputFull = [IO.Path]::GetFullPath($OutputDirectory)
    Assert-NoReparseChain $outputFull
    if ($outputFull.StartsWith($evidenceFull.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'gui_output_inside_evidence_root'
    }
    if (-not (Test-Path -LiteralPath $outputFull)) { New-Item -ItemType Directory -Path $outputFull | Out-Null }
    Assert-NoReparseChain $outputFull
    if (-not (Test-Path -LiteralPath $outputFull -PathType Container)) { throw 'gui_output_directory_invalid' }

    $caseDirectory = Join-Path $evidenceFull 'cases'
    Assert-NoReparseChain $caseDirectory
    if (-not (Test-Path -LiteralPath $caseDirectory -PathType Container)) { throw 'gui_case_directory_missing' }
    $caseFiles = @(Get-ChildItem -LiteralPath $caseDirectory -File -Filter '*.json')
    if ($caseFiles.Count -ne $ExpectedCases.Count) { throw 'gui_case_count_invalid' }

    $referenced = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $caseRecords = [Collections.Generic.List[object]]::new()
    $casesById = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $exeHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in $caseFiles) {
        Assert-NoReparseChain $file.FullName
        $relativeCasePath = [IO.Path]::GetRelativePath($evidenceFull, $file.FullName).Replace('\', '/')
        Register-EvidencePath $relativeCasePath $referenced
        $case = Read-StrictJson $file.FullName 'gui_case_json_invalid'
        Assert-ExactProperties $case @(
            'schemaVersion', 'releaseVersion', 'caseId', 'language', 'dpiPercent', 'startedAtUtc', 'completedAtUtc',
            'executable', 'environment', 'observations', 'screenshots', 'fullVideoLifecycle', 'representativeChecks', 'notes'
        )
        if ($case.notes -isnot [string]) { throw 'gui_notes_invalid' }
        $caseId = $case.caseId
        if ($caseId -isnot [string]) { throw 'gui_case_id_invalid' }
        Assert-ExactProperties $case.executable @('fileName', 'sha256', 'length')
        $sha = $case.executable.sha256
        if ($sha -isnot [string] -or $sha -notmatch '^[a-fA-F0-9]{64}$') { throw 'gui_executable_sha_invalid' }
        $null = $exeHashes.Add($sha.ToLowerInvariant())
        $caseRecords.Add([pscustomobject]@{ CaseId = $caseId; Case = $case; File = $file })
    }
    foreach ($record in $caseRecords) {
        if (-not $casesById.TryAdd($record.CaseId, $record.Case)) { throw 'gui_case_duplicate' }
    }
    foreach ($record in $caseRecords) {
        if ($record.File.BaseName -cne $record.CaseId) { throw 'gui_case_filename_mismatch' }
    }
    if ($exeHashes.Count -ne 1) { throw 'gui_executable_sha_mixed' }
    if (@($exeHashes)[0] -cne $actualExe.sha256) { throw 'gui_executable_hash_mismatch' }
    foreach ($expectedId in $ExpectedCases.Keys) {
        if (-not $casesById.ContainsKey($expectedId)) { throw 'gui_case_set_invalid' }
    }

    $seenScreenshotPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $probeRequests = [Collections.Generic.List[object]]::new()
    $representativeCoverage = [ordered]@{
        mp3Conversion = [Collections.Generic.List[string]]::new()
        settingsSaveRestartRestore = [Collections.Generic.List[string]]::new()
        legacySettingsTransition = [Collections.Generic.List[string]]::new()
    }

    foreach ($caseId in $ExpectedCases.Keys) {
        $definition = $ExpectedCases[$caseId]
        $case = $casesById[$caseId]
        if ($case.schemaVersion -cne 2) { throw 'gui_schema_version_invalid' }
        if ($case.releaseVersion -cne $ReleaseVersion) { throw 'gui_release_version_invalid' }
        if ($case.language -cne $definition.language) { throw 'gui_language_mismatch' }
        if (-not (Test-IntegerValue $case.dpiPercent) -or [int]$case.dpiPercent -ne $definition.dpi) { throw 'gui_dpi_mismatch' }
        $started = ConvertFrom-EvidenceTimestamp $case.startedAtUtc 'gui_started_timestamp_invalid'
        $completed = ConvertFrom-EvidenceTimestamp $case.completedAtUtc 'gui_completed_timestamp_invalid'
        if ($completed -lt $started) { throw 'gui_case_interval_invalid' }

        if ($case.executable.fileName -cne 'ytdlp-interface.exe') { throw 'gui_executable_filename_invalid' }
        if (-not (Test-IntegerValue $case.executable.length) -or [long]$case.executable.length -ne $actualExe.length) {
            throw 'gui_executable_length_mismatch'
        }

        Assert-ExactProperties $case.environment @('observedLanguage', 'observedDpiPercent', 'recordedAtUtc')
        if ($case.environment.observedLanguage -cne $definition.language) { throw 'gui_language_mismatch' }
        if (-not (Test-IntegerValue $case.environment.observedDpiPercent) -or
            [int]$case.environment.observedDpiPercent -ne $definition.dpi) { throw 'gui_dpi_mismatch' }
        $null = Assert-TimestampInCase $case.environment.recordedAtUtc $started $completed

        Assert-ExactProperties $case.observations $ObservationNames
        foreach ($observationName in $ObservationNames) {
            $observation = $case.observations.PSObject.Properties[$observationName].Value
            if ($null -eq $observation) { throw "gui_observation_missing: $observationName" }
            Assert-ExactProperties $observation @('result', 'observedAtUtc')
            if ($observation.result -isnot [bool]) { throw "gui_observation_not_boolean: $observationName" }
            if (-not $observation.result) {
                if ($observationName -ceq 'noClipping') { throw 'gui_clipping_detected' }
                throw "gui_observation_failed: $observationName"
            }
            $null = Assert-TimestampInCase $observation.observedAtUtc $started $completed
        }

        if ($case.screenshots -isnot [Array] -or @($case.screenshots).Count -eq 0) { throw 'gui_screenshots_missing' }
        $caseScreenshotPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($screenshot in @($case.screenshots)) {
            Assert-ExactProperties $screenshot @('path', 'sha256', 'length', 'width', 'height', 'capturedAtUtc')
            $file = Assert-EvidenceFile ([pscustomobject]@{
                path = $screenshot.path
                sha256 = $screenshot.sha256
                length = $screenshot.length
            }) $referenced
            if ([IO.Path]::GetExtension($file.RelativePath) -cne '.png') { throw 'gui_screenshot_not_png' }
            if (-not $seenScreenshotPaths.Add($file.RelativePath)) { throw 'gui_screenshot_reused_between_cases' }
            $null = $caseScreenshotPaths.Add($file.RelativePath)
            $dimensions = Get-DecodedPngDimensions $file.FullPath
            if ($dimensions.Width -lt 640 -or $dimensions.Height -lt 480) { throw 'gui_screenshot_too_small' }
            if (-not (Test-IntegerValue $screenshot.width) -or -not (Test-IntegerValue $screenshot.height) -or
                [int64]$screenshot.width -ne $dimensions.Width -or [int64]$screenshot.height -ne $dimensions.Height) {
                throw 'gui_screenshot_dimensions_mismatch'
            }
            $null = Assert-TimestampInCase $screenshot.capturedAtUtc $started $completed
        }

        $lifecycle = $case.fullVideoLifecycle
        if ($definition.lifecycle -and $null -eq $lifecycle) { throw 'gui_lifecycle_missing' }
        if ($null -ne $lifecycle) {
            Assert-ExactProperties $lifecycle @('completed', 'observedAtUtc', 'expectedWidth', 'expectedHeight', 'output')
            Assert-BooleanTrue $lifecycle.completed 'gui_lifecycle_not_boolean' 'gui_lifecycle_failed'
            $null = Assert-TimestampInCase $lifecycle.observedAtUtc $started $completed
            if (-not (Test-IntegerValue $lifecycle.expectedWidth) -or -not (Test-IntegerValue $lifecycle.expectedHeight) -or
                [int]$lifecycle.expectedWidth -le 0 -or [int]$lifecycle.expectedHeight -le 0 -or
                [Math]::Min([int]$lifecycle.expectedWidth, [int]$lifecycle.expectedHeight) -ne 1080) {
                throw 'gui_lifecycle_expected_resolution_invalid'
            }
            $media = Assert-EvidenceFile $lifecycle.output $referenced
            if ([IO.Path]::GetExtension($media.RelativePath) -notin @('.mp4', '.mkv', '.webm')) { throw 'gui_lifecycle_output_invalid' }
            $probeRequests.Add([pscustomobject]@{
                CaseId = $caseId
                Kind = 'video'
                Media = $media
                ExpectedWidth = [int]$lifecycle.expectedWidth
                ExpectedHeight = [int]$lifecycle.expectedHeight
            })
        }

        Assert-ExactProperties $case.representativeChecks $RepresentativeNames
        foreach ($checkName in $RepresentativeNames) {
            $check = $case.representativeChecks.PSObject.Properties[$checkName].Value
            if ($null -eq $check) { continue }
            if ($checkName -ceq 'mp3Conversion') {
                Assert-ExactProperties $check @('result', 'observedAtUtc', 'output')
            }
            else {
                Assert-ExactProperties $check @('result', 'observedAtUtc', 'screenshotPath')
            }
            if ($check.result -isnot [bool]) { throw "gui_representative_check_not_boolean: $checkName" }
            if (-not $check.result) { throw "gui_representative_check_failed: $checkName" }
            $null = Assert-TimestampInCase $check.observedAtUtc $started $completed
            if ($checkName -ceq 'mp3Conversion') {
                $mp3 = Assert-EvidenceFile $check.output $referenced
                if ([IO.Path]::GetExtension($mp3.RelativePath) -cne '.mp3') { throw 'gui_mp3_output_invalid' }
                $probeRequests.Add([pscustomobject]@{ CaseId = $caseId; Kind = 'mp3'; Media = $mp3; ExpectedWidth = 0; ExpectedHeight = 0 })
            }
            elseif ($check.screenshotPath -isnot [string] -or -not $caseScreenshotPaths.Contains($check.screenshotPath)) {
                throw "gui_representative_screenshot_invalid: $checkName"
            }
            $representativeCoverage[$checkName].Add($caseId)
        }
    }

    foreach ($checkName in $RepresentativeNames) {
        if ($representativeCoverage[$checkName].Count -eq 0) { throw "gui_representative_check_missing: $checkName" }
    }
    Assert-ExactEvidenceFileSet $referenced

    $finalName = 'gui-validation-v2.19.1-karon.2'
    $finalPath = Join-Path $outputFull $finalName
    if (Test-Path -LiteralPath $finalPath) { throw 'gui_validation_output_exists' }
    $partialPath = Join-Path $outputFull ('.' + $finalName + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $partialPath | Out-Null
    try {
        $probeDirectory = Join-Path $partialPath 'probes'
        New-Item -ItemType Directory -Path $probeDirectory | Out-Null
        $generatedProbes = [Collections.Generic.List[object]]::new()
        foreach ($request in $probeRequests) {
            $probe = Invoke-SealedFfprobe $candidate.FfprobePath $request.Media.FullPath
            Assert-ProbeMatchesRequest $probe $request
            $canonical = ConvertTo-CanonicalProbe $probe
            $relativeProbe = "probes/$($request.CaseId)-$($request.Kind).ffprobe.json"
            $probePath = Join-Path $partialPath ($relativeProbe.Replace('/', '\'))
            [IO.File]::WriteAllText($probePath, (ConvertTo-DeterministicJsonText $canonical), [Text.UTF8Encoding]::new($false))
            $probeItem = Get-Item -LiteralPath $probePath
            $generatedProbes.Add([ordered]@{
                caseId = $request.CaseId
                kind = $request.Kind
                path = $relativeProbe
                sha256 = Get-Sha256 $probePath
                length = $probeItem.Length
            })
        }

        $evidenceFiles = Get-InputEvidenceManifest $referenced
        $summary = [ordered]@{
            schemaVersion = 2
            releaseVersion = $ReleaseVersion
            status = 'PASS'
            candidate = $candidate.Public
            cases = @($ExpectedCases.Keys)
            fullVideoLifecycleCases = @('ko-KR-100', 'en-US-200')
            representativeChecks = [ordered]@{
                mp3Conversion = @($representativeCoverage.mp3Conversion)
                settingsSaveRestartRestore = @($representativeCoverage.settingsSaveRestartRestore)
                legacySettingsTransition = @($representativeCoverage.legacySettingsTransition)
            }
            generatedProbes = @($generatedProbes)
            evidenceFileCount = $evidenceFiles.Count
            evidenceManifestFile = 'gui-validation-evidence-manifest.json'
        }
        $manifest = [ordered]@{
            schemaVersion = 2
            releaseVersion = $ReleaseVersion
            candidate = $candidate.Public
            evidenceFiles = @($evidenceFiles)
            generatedProbeFiles = @($generatedProbes)
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
