#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Initialize', 'RecordEnvironment', 'RecordObservation', 'AddScreenshot', 'AttachVideoLifecycle', 'RecordMp3', 'RecordSettingsRestore', 'RecordLegacyTransition', 'Finalize')]
    [string] $Action,
    [string] $EvidenceRoot,
    [string] $CasePath,
    [string] $CandidateExePath,
    [ValidateSet('ko-KR', 'en-US')] [string] $Language,
    [ValidateSet(100, 150, 200)] [int] $DpiPercent,
    [ValidateSet('ko-KR', 'en-US')] [string] $ObservedLanguage,
    [ValidateSet(100, 150, 200)] [int] $ObservedDpiPercent,
    [ValidateSet('launch', 'downloadType', 'quality1080p', 'quality720p', 'qualityBest', 'expectedResolution', 'queueRegistration', 'progress', 'completion', 'advancedNavigation', 'noClipping')]
    [string] $Observation,
    [ValidateSet('true', 'false')] [string] $Result,
    [string] $EvidenceFilePath,
    [string] $Label,
    [int] $ExpectedWidth,
    [int] $ExpectedHeight,
    [string] $ScreenshotReferencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ReleaseVersion = 'v2.19.1-karon.2'
$ObservationNames = @('launch', 'downloadType', 'quality1080p', 'quality720p', 'qualityBest', 'expectedResolution', 'queueRegistration', 'progress', 'completion', 'advancedNavigation', 'noClipping')

function Get-UtcText {
    [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
}

function Get-Sha256 {
    param([string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonAtomic {
    param([string] $Path, [object] $Value, [bool] $Overwrite)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
    $partial = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N'))
    try {
        $json = (($Value | ConvertTo-Json -Depth 64).Replace("`r`n", "`n") + "`n")
        $stream = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally { $stream.Dispose() }
        [IO.File]::Move($partial, $Path, $Overwrite)
    }
    finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
}

function Read-Case {
    if ([string]::IsNullOrWhiteSpace($CasePath) -or -not (Test-Path -LiteralPath $CasePath -PathType Leaf)) { throw 'operator_case_missing' }
    Get-Content -LiteralPath $CasePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64 -DateKind String
}

function Get-CaseEvidenceRoot {
    $caseDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($CasePath))
    if ([IO.Path]::GetFileName($caseDirectory) -cne 'cases') { throw 'operator_case_path_invalid' }
    Split-Path -Parent $caseDirectory
}

function Assert-SourceFile {
    param([string] $Path, [string] $ErrorId)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw $ErrorId }
    $item = Get-Item -LiteralPath $Path
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 0) { throw $ErrorId }
    $item
}

function Get-PngDimensions {
    param([string] $Path)
    try { Add-Type -AssemblyName System.Drawing.Common -ErrorAction Stop }
    catch { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }

    $stream = $null
    $image = $null
    $bitmap = $null
    $bitmapData = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $image = [Drawing.Image]::FromStream($stream, $true, $true)
        if ($image.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid) { throw 'not_png' }
        $bitmap = [Drawing.Bitmap]::new($image)
        $rectangle = [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height)
        $bitmapData = $bitmap.LockBits($rectangle, [Drawing.Imaging.ImageLockMode]::ReadOnly, $bitmap.PixelFormat)
        $bitmap.UnlockBits($bitmapData)
        $bitmapData = $null
        $width = $bitmap.Width
        $height = $bitmap.Height
    }
    catch { throw 'operator_screenshot_invalid' }
    finally {
        if ($null -ne $bitmapData -and $null -ne $bitmap) { $bitmap.UnlockBits($bitmapData) }
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $image) { $image.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
    if ($width -lt 640 -or $height -lt 480) { throw 'operator_screenshot_too_small' }
    [pscustomobject]@{ Width = [int64]$width; Height = [int64]$height }
}

function Copy-EvidenceFile {
    param([string] $Source, [string] $Subdirectory, [string] $Name)
    $root = Get-CaseEvidenceRoot
    $destinationDirectory = Join-Path $root $Subdirectory
    if (-not (Test-Path -LiteralPath $destinationDirectory)) { New-Item -ItemType Directory -Path $destinationDirectory | Out-Null }
    $destination = Join-Path $destinationDirectory $Name
    if (Test-Path -LiteralPath $destination) { throw 'operator_evidence_output_exists' }
    [IO.File]::Copy((Assert-SourceFile $Source 'operator_evidence_source_invalid').FullName, $destination, $false)
    $item = Get-Item -LiteralPath $destination
    [pscustomobject]@{
        RelativePath = ($Subdirectory + '/' + $Name)
        FullPath = $destination
        Sha256 = Get-Sha256 $destination
        Length = $item.Length
    }
}

function Convert-Result {
    if ([string]::IsNullOrWhiteSpace($Result)) { throw 'operator_explicit_result_required' }
    $Result -ceq 'true'
}

try {
    if ($Action -ceq 'Initialize') {
        if ([string]::IsNullOrWhiteSpace($EvidenceRoot) -or [string]::IsNullOrWhiteSpace($CandidateExePath) -or
            [string]::IsNullOrWhiteSpace($Language) -or $DpiPercent -notin @(100, 150, 200)) {
            throw 'operator_initialize_arguments_invalid'
        }
        $exe = Assert-SourceFile $CandidateExePath 'operator_candidate_executable_invalid'
        if ($exe.Name -cne 'ytdlp-interface.exe') { throw 'operator_candidate_executable_invalid' }
        $caseId = "$Language-$DpiPercent"
        $caseDirectory = Join-Path ([IO.Path]::GetFullPath($EvidenceRoot)) 'cases'
        foreach ($directory in @($caseDirectory, (Join-Path $EvidenceRoot 'screenshots'), (Join-Path $EvidenceRoot 'artifacts'))) {
            if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
        }
        $path = Join-Path $caseDirectory "$caseId.json"
        if (Test-Path -LiteralPath $path) { throw 'operator_case_exists' }
        $observations = [ordered]@{}
        foreach ($name in $ObservationNames) { $observations[$name] = $null }
        $case = [ordered]@{
            schemaVersion = 2
            releaseVersion = $ReleaseVersion
            caseId = $caseId
            language = $Language
            dpiPercent = $DpiPercent
            startedAtUtc = Get-UtcText
            completedAtUtc = $null
            executable = [ordered]@{ fileName = 'ytdlp-interface.exe'; sha256 = Get-Sha256 $exe.FullName; length = $exe.Length }
            environment = [ordered]@{ observedLanguage = $null; observedDpiPercent = $null; recordedAtUtc = $null }
            observations = $observations
            screenshots = @()
            fullVideoLifecycle = $null
            representativeChecks = [ordered]@{
                mp3Conversion = $null
                settingsSaveRestartRestore = $null
                legacySettingsTransition = $null
            }
            notes = ''
        }
        Write-JsonAtomic $path $case $false
        Write-Host $path
        exit 0
    }

    $case = Read-Case
    $now = Get-UtcText
    if ($Action -ceq 'RecordEnvironment') {
        if ([string]::IsNullOrWhiteSpace($ObservedLanguage) -or $ObservedDpiPercent -notin @(100, 150, 200)) { throw 'operator_environment_arguments_invalid' }
        $case.environment.observedLanguage = $ObservedLanguage
        $case.environment.observedDpiPercent = $ObservedDpiPercent
        $case.environment.recordedAtUtc = $now
    }
    elseif ($Action -ceq 'RecordObservation') {
        if ([string]::IsNullOrWhiteSpace($Observation)) { throw 'operator_observation_missing' }
        $case.observations.$Observation = [ordered]@{ result = Convert-Result; observedAtUtc = $now }
    }
    elseif ($Action -ceq 'AddScreenshot') {
        if ([string]::IsNullOrWhiteSpace($Label) -or $Label -notmatch '^[a-z0-9][a-z0-9-]{0,39}$') { throw 'operator_screenshot_label_invalid' }
        $source = Assert-SourceFile $EvidenceFilePath 'operator_screenshot_missing'
        if ($source.Extension -cne '.png') { throw 'operator_screenshot_invalid' }
        $dimensions = Get-PngDimensions $source.FullName
        $copy = Copy-EvidenceFile $source.FullName 'screenshots' ($case.caseId + '-' + $Label + '.png')
        $record = [ordered]@{
            path = $copy.RelativePath
            sha256 = $copy.Sha256
            length = $copy.Length
            width = $dimensions.Width
            height = $dimensions.Height
            capturedAtUtc = $now
        }
        $case.screenshots = @($case.screenshots) + @($record)
    }
    elseif ($Action -ceq 'AttachVideoLifecycle') {
        if ($ExpectedWidth -le 0 -or $ExpectedHeight -le 0) { throw 'operator_lifecycle_resolution_invalid' }
        $media = Assert-SourceFile $EvidenceFilePath 'operator_lifecycle_output_missing'
        if ($media.Extension -notin @('.mp4', '.mkv', '.webm')) { throw 'operator_lifecycle_output_invalid' }
        $mediaCopy = Copy-EvidenceFile $media.FullName 'artifacts' ($case.caseId + '-video' + $media.Extension.ToLowerInvariant())
        $case.fullVideoLifecycle = [ordered]@{
            completed = Convert-Result
            observedAtUtc = $now
            expectedWidth = $ExpectedWidth
            expectedHeight = $ExpectedHeight
            output = [ordered]@{ path = $mediaCopy.RelativePath; sha256 = $mediaCopy.Sha256; length = $mediaCopy.Length }
        }
    }
    elseif ($Action -ceq 'RecordMp3') {
        $observed = Convert-Result
        $record = [ordered]@{ result = $observed; observedAtUtc = $now }
        if ($observed) {
            $mp3 = Assert-SourceFile $EvidenceFilePath 'operator_mp3_output_missing'
            if ($mp3.Extension -cne '.mp3') { throw 'operator_mp3_output_invalid' }
            $copy = Copy-EvidenceFile $mp3.FullName 'artifacts' ($case.caseId + '-audio.mp3')
            $record.output = [ordered]@{ path = $copy.RelativePath; sha256 = $copy.Sha256; length = $copy.Length }
        }
        $case.representativeChecks.mp3Conversion = $record
    }
    elseif ($Action -in @('RecordSettingsRestore', 'RecordLegacyTransition')) {
        $observed = Convert-Result
        $record = [ordered]@{ result = $observed; observedAtUtc = $now }
        if ($observed) {
            if ([string]::IsNullOrWhiteSpace($ScreenshotReferencePath) -or
                @($case.screenshots | Where-Object { $_.path -ceq $ScreenshotReferencePath }).Count -ne 1) {
                throw 'operator_representative_screenshot_invalid'
            }
            $record.screenshotPath = $ScreenshotReferencePath
        }
        if ($Action -ceq 'RecordSettingsRestore') { $case.representativeChecks.settingsSaveRestartRestore = $record }
        else { $case.representativeChecks.legacySettingsTransition = $record }
    }
    elseif ($Action -ceq 'Finalize') {
        $case.completedAtUtc = $now
    }
    else { throw 'operator_action_not_implemented' }

    Write-JsonAtomic ([IO.Path]::GetFullPath($CasePath)) $case $true
    Write-Host ([IO.Path]::GetFullPath($CasePath))
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
