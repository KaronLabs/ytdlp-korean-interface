[CmdletBinding()]
param(
    [string] $CandidateRoot,
    [string] $ParentRuntime,
    [string] $PythonPath,
    [string] $DownloadsPath,
    [string] $ExpectedCandidateManifestSha256,
    [switch] $Run,
    [switch] $OperatorGuided,
    [scriptblock] $AutomationCommand
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'candidate-manifest.psm1') -Force
$smokeRun = $Run
$smokeParentRuntime = $ParentRuntime
$smokeDownloadsPath = $DownloadsPath
$smokeExpectedCandidateManifestSha256 = $ExpectedCandidateManifestSha256
. (Join-Path $PSScriptRoot 'build-candidate.ps1')

function Test-LocalhostUrl {
    param([Parameter(Mandatory = $true)] [string] $Url)
    try { $uri = [Uri]$Url } catch { return $false }
    return $uri.Scheme -eq 'http' -and $uri.Host -eq '127.0.0.1' -and $uri.Port -gt 0 -and $uri.AbsolutePath -eq '/input.mp4'
}

function Test-PathOverlap {
    param([Parameter(Mandatory = $true)] [string] $First, [Parameter(Mandatory = $true)] [string] $Second)
    return (Test-PathContained -Root $First -Path $Second) -or (Test-PathContained -Root $Second -Path $First) -or
        ([IO.Path]::GetFullPath($First).TrimEnd('\', '/') -eq [IO.Path]::GetFullPath($Second).TrimEnd('\', '/'))
}

function Stop-TrackedProcesses {
    param(
        [object[]] $Processes,
        [scriptblock] $StopAction = { param($process) Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue },
        [scriptblock] $WaitAction = { param($process, $milliseconds) $process.WaitForExit($milliseconds) },
        [int] $WaitMilliseconds = 5000
    )
    foreach ($process in @($Processes)) {
        if ($null -ne $process -and -not $process.HasExited) {
            & $StopAction $process
            if (-not (& $WaitAction $process $WaitMilliseconds)) { throw 'process_cleanup_timeout' }
        }
    }
}

function Test-AutomationCompletion {
    param([object] $Marker, [int] $GuiProcessId, [string] $Url, [string] $OutputDirectory)
    if ($null -eq $Marker) { return $false }
    foreach ($name in @('Completed', 'GuiProcessId', 'Url', 'OutputDirectory')) {
        if ($null -eq $Marker.PSObject.Properties[$name]) { return $false }
    }
    return [bool]$Marker.Completed -and [int]$Marker.GuiProcessId -eq $GuiProcessId -and
        [string]$Marker.Url -eq $Url -and [IO.Path]::GetFullPath([string]$Marker.OutputDirectory) -eq [IO.Path]::GetFullPath($OutputDirectory)
}

function Test-SmokeOutput {
    param([Parameter(Mandatory = $true)] [string] $OutputDirectory, [datetime] $StartedAtUtc = [DateTime]::MinValue, [Parameter(Mandatory = $true)] [scriptblock] $FfprobeAction)
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { return [pscustomobject]@{ Valid = $false; ReasonCode = 'output_missing' } }
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File -Filter '*.part').Count -ne 0) { return [pscustomobject]@{ Valid = $false; ReasonCode = 'part_file' } }
    $mp3 = @(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File -Filter '*.mp3' | Where-Object { $_.Length -gt 0 }) | Select-Object -First 1
    if ($null -eq $mp3) { return [pscustomobject]@{ Valid = $false; ReasonCode = 'mp3_missing' } }
    if ($mp3.CreationTimeUtc -lt $StartedAtUtc -or $mp3.LastWriteTimeUtc -lt $StartedAtUtc) { return [pscustomobject]@{ Valid = $false; ReasonCode = 'stale_output' } }
    $probe = ([string](& $FfprobeAction $mp3.FullName)) -replace "`r`n", "`n"
    if ($probe -notmatch '(?m)^codec_name=mp3$') { return [pscustomobject]@{ Valid = $false; ReasonCode = 'codec_not_mp3' } }
    $durationMatch = [regex]::Match($probe, '(?m)^duration=([0-9]+(?:\.[0-9]+)?)$')
    if (-not $durationMatch.Success -or [double]$durationMatch.Groups[1].Value -le 0) { return [pscustomobject]@{ Valid = $false; ReasonCode = 'duration_invalid' } }
    return [pscustomobject]@{ Valid = $true; ReasonCode = 'ok'; Mp3Path = $mp3.FullName; Duration = [double]$durationMatch.Groups[1].Value }
}

function New-SmokeSuccessEvidence {
    param(
        [Parameter(Mandatory = $true)] [string] $Workspace,
        [Parameter(Mandatory = $true)] [string] $OutputDirectory,
        [Parameter(Mandatory = $true)] [string] $Mp3Path,
        [Parameter(Mandatory = $true)] [string] $SettingsPath,
        [Parameter(Mandatory = $true)] [string] $FfprobeOutput,
        [string] $EvidenceDirectory,
        [string] $RunId
    )
    $workspaceFull = [IO.Path]::GetFullPath($Workspace)
    $outputFull = [IO.Path]::GetFullPath($OutputDirectory)
    $mp3Full = [IO.Path]::GetFullPath($Mp3Path)
    $settingsFull = [IO.Path]::GetFullPath($SettingsPath)
    if (-not (Test-PathContained -Root $workspaceFull -Path $outputFull) -or -not (Test-PathContained -Root $outputFull -Path $mp3Full) -or
        -not (Test-PathContained -Root $workspaceFull -Path $settingsFull) -or -not (Test-Path -LiteralPath $mp3Full -PathType Leaf) -or
        -not (Test-Path -LiteralPath $settingsFull -PathType Leaf) -or @(Get-ChildItem -LiteralPath $outputFull -Recurse -File -Filter '*.part').Count -ne 0) { throw 'smoke_success_evidence_invalid' }
    $probe = $FfprobeOutput -replace "`r`n", "`n"
    if ($probe -notmatch '(?m)^codec_name=mp3$') { throw 'smoke_success_evidence_invalid' }
    $durationMatch = [regex]::Match($probe, '(?m)^duration=([0-9]+(?:\.[0-9]+)?)$')
    if (-not $durationMatch.Success -or [double]$durationMatch.Groups[1].Value -le 0) { throw 'smoke_success_evidence_invalid' }
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $ffprobeSha256 = ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($FfprobeOutput)))).Replace('-', '') }
    finally { $hasher.Dispose() }
    $evidence = [ordered]@{
        relativePath = $mp3Full.Substring($workspaceFull.Length).TrimStart('\', '/')
        sha256 = (Get-FileHash -LiteralPath $mp3Full -Algorithm SHA256).Hash.ToUpperInvariant()
        length = (Get-Item -LiteralPath $mp3Full).Length
        duration = [double]$durationMatch.Groups[1].Value
        settingsSha256 = (Get-FileHash -LiteralPath $settingsFull -Algorithm SHA256).Hash.ToUpperInvariant()
        ffprobeSha256 = $ffprobeSha256
        noPartFiles = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($EvidenceDirectory) -or -not [string]::IsNullOrWhiteSpace($RunId)) {
        if ([string]::IsNullOrWhiteSpace($EvidenceDirectory) -or [string]::IsNullOrWhiteSpace($RunId)) { throw 'smoke_success_evidence_invalid' }
        $artifactRoot = Join-Path (Join-Path $EvidenceDirectory 'artifacts') $RunId
        [IO.Directory]::CreateDirectory($artifactRoot) | Out-Null
        Copy-Item -LiteralPath $mp3Full -Destination (Join-Path $artifactRoot 'output.mp3')
        Copy-Item -LiteralPath $settingsFull -Destination (Join-Path $artifactRoot 'ytdlp-interface.json')
        [IO.File]::WriteAllText((Join-Path $artifactRoot 'ffprobe.txt'), $FfprobeOutput, [Text.UTF8Encoding]::new($false))
        $evidence.retainedMp3 = 'artifacts/' + $RunId + '/output.mp3'
        $evidence.retainedSettings = 'artifacts/' + $RunId + '/ytdlp-interface.json'
        $evidence.retainedFfprobe = 'artifacts/' + $RunId + '/ffprobe.txt'
        if ((Get-FileHash -LiteralPath (Join-Path $artifactRoot 'output.mp3') -Algorithm SHA256).Hash -cne $evidence.sha256 -or
            (Get-FileHash -LiteralPath (Join-Path $artifactRoot 'ytdlp-interface.json') -Algorithm SHA256).Hash -cne $evidence.settingsSha256 -or
            (Get-FileHash -LiteralPath (Join-Path $artifactRoot 'ffprobe.txt') -Algorithm SHA256).Hash -cne $evidence.ffprobeSha256) { throw 'smoke_success_evidence_invalid' }
    }
    return $evidence
}

function Complete-SmokeWorkspace {
    param(
        [string] $Workspace,
        [string] $EvidenceDirectory,
        [bool] $Succeeded,
        [string] $ReasonCode,
        [string] $RunId,
        [string] $Mode,
        [object] $OutputEvidence,
        [string] $CandidateManifestSha256,
        [object] $ProofEvidence,
        [object] $ExecutionAttestation,
        [bool] $CleanupSucceeded = $true
    )
    if ([string]::IsNullOrWhiteSpace($RunId)) { throw 'smoke_run_id_required' }
    if ($Mode -notin @('operator-guided', 'artifact-only')) { throw 'smoke_mode_invalid' }
    if ($null -eq $ProofEvidence) { $ProofEvidence = [ordered]@{ artifactValidated = $Succeeded; guiInteractionProven = $false; operatorAttested = $false } }
    foreach ($name in @('artifactValidated', 'guiInteractionProven', 'operatorAttested')) {
        $hasProofField = if ($ProofEvidence -is [Collections.IDictionary]) { $ProofEvidence.Contains($name) } else { $null -ne $ProofEvidence.PSObject.Properties[$name] }
        if (-not $hasProofField) { throw 'smoke_success_evidence_invalid' }
    }
    if ($Mode -eq 'artifact-only' -and ([bool]$ProofEvidence.guiInteractionProven -or [bool]$ProofEvidence.operatorAttested)) { throw 'smoke_success_evidence_invalid' }
    if ($Succeeded) {
        if ($CandidateManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $null -eq $OutputEvidence) { throw 'smoke_success_evidence_invalid' }
        if ([string]$OutputEvidence.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]::IsNullOrWhiteSpace([string]$OutputEvidence.relativePath) -or [IO.Path]::IsPathRooted([string]$OutputEvidence.relativePath) -or [long]$OutputEvidence.length -le 0 -or [double]$OutputEvidence.duration -le 0) { throw 'smoke_success_evidence_invalid' }
        if (-not [bool]$ProofEvidence.artifactValidated -or [string]$OutputEvidence.settingsSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
            [string]$OutputEvidence.ffprobeSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or -not [bool]$OutputEvidence.noPartFiles) { throw 'smoke_success_evidence_invalid' }
    }
    $runs = Join-Path $EvidenceDirectory 'runs'; [IO.Directory]::CreateDirectory($runs) | Out-Null
    $manifestPath = Join-Path $runs ($RunId + '.json')
    $manifest = [ordered]@{
        schemaVersion = 2
        runId = $RunId
        succeeded = $Succeeded
        reasonCode = $ReasonCode
        mode = $Mode
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        workspaceId = (Split-Path -Leaf $Workspace)
        candidateManifestSha256 = $CandidateManifestSha256
        execution = $ExecutionAttestation
        proof = $ProofEvidence
        cleanupSucceeded = $CleanupSucceeded
        output = $OutputEvidence
    }
    $json = $manifest | ConvertTo-Json -Depth 5
    $stream = New-Object IO.FileStream($manifestPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $writer = New-Object IO.StreamWriter($stream, [Text.UTF8Encoding]::new($false))
        try { $writer.Write($json) }
        finally { $writer.Dispose() }
    }
    finally { $stream.Dispose() }
    if ($Succeeded -and (Test-Path -LiteralPath $Workspace)) { Remove-Item -LiteralPath $Workspace -Recurse -Force }
}

function Complete-SmokeRun {
    param(
        [string] $Workspace,
        [string] $EvidenceDirectory,
        [bool] $Succeeded,
        [string] $ReasonCode,
        [string] $RunId,
        [string] $Mode,
        [object] $OutputEvidence,
        [string] $CandidateManifestSha256,
        [object] $ProofEvidence,
        [object] $ExecutionAttestation,
        [scriptblock] $SuccessEvidenceAction,
        [Parameter(Mandatory = $true)] [scriptblock] $CleanupAction
    )
    $cleanupFailed = $false; $evidenceFailed = $false
    try {
        try { & $CleanupAction }
        catch {
            $cleanupFailed = $true
            $Succeeded = $false
            $ReasonCode = 'process_cleanup_timeout'
        }
        if (-not $cleanupFailed -and $Succeeded -and $null -ne $SuccessEvidenceAction) {
            try { $OutputEvidence = & $SuccessEvidenceAction }
            catch { $evidenceFailed = $true; $Succeeded = $false; $ReasonCode = 'smoke_success_evidence_invalid' }
        }
    }
    finally { Complete-SmokeWorkspace -Workspace $Workspace -EvidenceDirectory $EvidenceDirectory -Succeeded:$Succeeded -ReasonCode $ReasonCode -RunId $RunId -Mode $Mode -OutputEvidence $OutputEvidence -CandidateManifestSha256 $CandidateManifestSha256 -ProofEvidence $ProofEvidence -ExecutionAttestation $ExecutionAttestation -CleanupSucceeded:(-not $cleanupFailed) }
    if ($cleanupFailed) { throw 'process_cleanup_timeout' }
    if ($evidenceFailed) { throw 'smoke_success_evidence_invalid' }
}

function Set-SmokeCandidateOutputPath {
    param([Parameter(Mandatory = $true)] [string] $CandidateRoot, [Parameter(Mandatory = $true)] [string] $OutputDirectory)
    $settingsPath = Join-Path $CandidateRoot 'ytdlp-interface.json'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { throw 'candidate_settings_missing' }
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ($null -eq $settings.PSObject.Properties['outpath']) { $settings | Add-Member -NotePropertyName outpath -NotePropertyValue $OutputDirectory }
    else { $settings.outpath = $OutputDirectory }
    $temporaryPath = $settingsPath + '.smoke-staging.' + [Guid]::NewGuid().ToString('N')
    $backupPath = $settingsPath + '.smoke-backup.' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporaryPath, ($settings | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json | Out-Null
        [IO.File]::Replace($temporaryPath, $settingsPath, $backupPath, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
    }
}

function Copy-SealedCandidateForSmoke {
    param(
        [Parameter(Mandatory = $true)] [string] $CandidateRoot,
        [Parameter(Mandatory = $true)] [string] $Workspace,
        [string] $ExpectedCandidateManifestSha256
    )
    $candidate = [IO.Path]::GetFullPath($CandidateRoot)
    $manifestPath = Join-Path $candidate 'candidate-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'candidate_manifest_missing' }
    $manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $manifestSha256 = ([BitConverter]::ToString($hasher.ComputeHash($manifestBytes))).Replace('-', '') }
    finally { $hasher.Dispose() }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCandidateManifestSha256) -and $ExpectedCandidateManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'candidate_manifest_invalid' }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCandidateManifestSha256) -and $manifestSha256 -cne $ExpectedCandidateManifestSha256.ToUpperInvariant()) { throw 'candidate_manifest_digest_mismatch' }
    try { $manifest = [Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json }
    catch { throw 'candidate_manifest_invalid' }
    Assert-CandidateManifestSeal -CandidateRoot $candidate -Manifest $manifest | Out-Null
    if ($null -eq $manifest.files -or @($manifest.files).Count -eq 0) { throw 'candidate_manifest_invalid' }
    $execution = Join-Path $Workspace 'candidate'
    [IO.Directory]::CreateDirectory($execution) | Out-Null
    $paths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($manifest.files)) {
        foreach ($name in @('path', 'sha256', 'length')) { if ($null -eq $entry.PSObject.Properties[$name]) { throw 'candidate_manifest_invalid' } }
        $relative = [string]$entry.path
        $entryLength = 0L
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($relative) -or
            [string]$entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or -not [long]::TryParse([string]$entry.length, [ref]$entryLength) -or $entryLength -lt 0) { throw 'candidate_manifest_invalid' }
        $source = Join-Path $candidate $relative
        $destination = Join-Path $execution $relative
        if (-not $paths.Add([IO.Path]::GetFullPath($source))) { throw 'candidate_manifest_invalid' }
        if (-not (Test-PathContained -Root $candidate -Path $source) -or -not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'candidate_manifest_invalid' }
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToUpperInvariant() -cne ([string]$entry.sha256).ToUpperInvariant() -or (Get-Item -LiteralPath $source).Length -ne $entryLength) { throw 'candidate_manifest_mismatch' }
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToUpperInvariant() -cne ([string]$entry.sha256).ToUpperInvariant()) { throw 'candidate_copy_mismatch' }
    }
    [IO.File]::WriteAllBytes((Join-Path $execution 'candidate-manifest.json'), $manifestBytes)
    return $execution
}

function Get-SmokeExecutionAttestation {
    param([Parameter(Mandatory = $true)] [string] $ExecutionCandidate, [Parameter(Mandatory = $true)] [string] $BaseCandidateManifestSha256)
    $settingsPath = Join-Path $ExecutionCandidate 'ytdlp-interface.json'
    if ($BaseCandidateManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or -not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { throw 'smoke_execution_attestation_invalid' }
    return [ordered]@{
        kind = 'settings-overlay'
        baseCandidateManifestSha256 = $BaseCandidateManifestSha256.ToUpperInvariant()
        settingsSha256 = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash.ToUpperInvariant()
    }
}

function Get-SmokeDownloadsKnownFolderPath {
    $module = Import-Module -Name (Join-Path $PSScriptRoot 'runtime-maintenance.psm1') -Force -PassThru
    return & $module { Get-DownloadsKnownFolderPath }
}

function Get-SmokeEvidenceDirectory {
    param([Parameter(Mandatory = $true)] [string] $DownloadsPath, [Parameter(Mandatory = $true)] [string] $CandidateRoot)
    $downloads = [IO.Path]::GetFullPath($DownloadsPath)
    $evidence = Join-Path $downloads 'ytdlp-interface-smoke-evidence'
    if (-not (Test-PathContained -Root $downloads -Path $evidence) -or (Test-PathOverlap -First $CandidateRoot -Second $evidence)) { throw 'workspace_containment' }
    return $evidence
}

function New-SmokeWorkspace {
    param([Parameter(Mandatory = $true)] [string] $DownloadsPath, [Parameter(Mandatory = $true)] [string] $RunId)
    $downloads = [IO.Path]::GetFullPath($DownloadsPath)
    if (-not (Test-Path -LiteralPath $downloads -PathType Container)) { throw 'downloads_missing' }
    $root = Join-Path $downloads ('ytdlp-interface-smoke-' + $RunId)
    $output = Join-Path $root 'output'
    if (-not (Test-PathContained -Root $downloads -Path $root) -or -not (Test-PathContained -Root $root -Path $output)) { throw 'workspace_containment' }
    [IO.Directory]::CreateDirectory($root) | Out-Null
    [IO.Directory]::CreateDirectory($output) | Out-Null
    return [pscustomobject]@{ Root = $root; OutputDirectory = $output }
}

function Invoke-SmokeProcess {
    param([Parameter(Mandatory = $true)] [string] $ReasonCode, [Parameter(Mandatory = $true)] [scriptblock] $Action)
    try { return & $Action }
    catch { throw $ReasonCode }
}

function Get-LoopbackPort {
    $listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Parse('127.0.0.1')), 0
    try { $listener.Start(); return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Wait-LoopbackServer {
    param([string] $Url, [int] $TimeoutSeconds = 10)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 1
            if ($response.StatusCode -eq 200) { return }
        }
        catch { Start-Sleep -Milliseconds 200 }
    }
    throw 'server_not_ready'
}

function Invoke-LocalhostSmoke {
    param([string] $CandidateRoot, [string] $ParentRuntime, [string] $PythonPath, [string] $DownloadsPath, [string] $ExpectedCandidateManifestSha256, [switch] $OperatorGuided, [scriptblock] $AutomationCommand)
    if ([string]::IsNullOrWhiteSpace($ParentRuntime)) { throw 'parent_runtime_required' }
    if ([string]::IsNullOrWhiteSpace($ExpectedCandidateManifestSha256)) { throw 'candidate_manifest_digest_required' }
    $candidate = [IO.Path]::GetFullPath($CandidateRoot)
    $parent = [IO.Path]::GetFullPath($ParentRuntime)
    if (Test-PathOverlap -First $candidate -Second $parent) { throw 'candidate_parent_overlap' }
    if (-not (Test-Path -LiteralPath (Join-Path $candidate 'ytdlp-interface.exe'))) { throw 'candidate_missing' }
    foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) { if (-not (Test-Path -LiteralPath (Join-Path $candidate $name))) { throw 'candidate_missing' } }
    $runId = [Guid]::NewGuid().ToString('N')
    if ([string]::IsNullOrWhiteSpace($DownloadsPath)) { $DownloadsPath = Get-SmokeDownloadsKnownFolderPath }
    $smokeWorkspace = New-SmokeWorkspace -DownloadsPath $DownloadsPath -RunId $runId
    $workspace = $smokeWorkspace.Root
    $output = $smokeWorkspace.OutputDirectory
    $evidence = Get-SmokeEvidenceDirectory -DownloadsPath $DownloadsPath -CandidateRoot $candidate
    $mode = if ($null -ne $AutomationCommand) { 'artifact-only' } else { 'operator-guided' }
    $manifestBindingSha256 = $ExpectedCandidateManifestSha256.ToUpperInvariant()
    if (-not (Test-PathContained -Root $workspace -Path $output) -or (Test-PathOverlap -First $parent -Second $workspace) -or (Test-PathOverlap -First $parent -Second $evidence)) { throw 'workspace_containment' }
    if (@(Get-ChildItem -LiteralPath $output -Force).Count -ne 0) { throw 'output_not_empty' }
    $processes = @(); $succeeded = $false; $reasonCode = 'smoke_failed'; $outputEvidence = $null; $successEvidenceAction = $null; $proofEvidence = $null; $executionAttestation = $null
    try {
        $media = Join-Path $workspace 'input.mp4'
        $executionCandidate = Copy-SealedCandidateForSmoke -CandidateRoot $candidate -Workspace $workspace -ExpectedCandidateManifestSha256 $manifestBindingSha256
        Set-SmokeCandidateOutputPath -CandidateRoot $executionCandidate -OutputDirectory $output
        $executionAttestation = Get-SmokeExecutionAttestation -ExecutionCandidate $executionCandidate -BaseCandidateManifestSha256 $manifestBindingSha256
        Invoke-SmokeProcess -ReasonCode 'fixture_generation_failed' -Action { Invoke-CheckedProcess -FilePath (Join-Path $executionCandidate 'ffmpeg.exe') -Arguments @('-y', '-f', 'lavfi', '-i', 'color=c=black:s=320x240:r=25:d=2', '-f', 'lavfi', '-i', 'sine=frequency=1000:duration=2', '-shortest', '-t', '2', $media) -Name 'smoke fixture generation' } | Out-Null
        $port = Get-LoopbackPort
        $url = "http://127.0.0.1:$port/input.mp4"
        if (-not (Test-LocalhostUrl -Url $url)) { throw 'url_rejected' }
        if ([string]::IsNullOrWhiteSpace($PythonPath)) {
            $python = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $python) { throw 'python_missing' }
            $PythonPath = $python.Source
        }
        if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw 'python_missing' }
        try { Invoke-CheckedProcess -FilePath $PythonPath -Arguments @('--version') -Name 'Python runtime check' | Out-Null }
        catch { throw 'python_missing' }
        $server = Start-Process -FilePath $PythonPath -ArgumentList @('-m', 'http.server', $port, '--bind', '127.0.0.1', '--directory', $workspace) -PassThru -RedirectStandardOutput (Join-Path $workspace 'server.out') -RedirectStandardError (Join-Path $workspace 'server.err')
        $processes += $server
        Wait-LoopbackServer -Url $url
        $startedAtUtc = [DateTime]::UtcNow
        $gui = Start-Process -FilePath (Join-Path $executionCandidate 'ytdlp-interface.exe') -WorkingDirectory $executionCandidate -PassThru
        $processes += $gui
        Start-Sleep -Seconds 1; $gui.Refresh()
        if ($gui.HasExited) { throw 'gui_start_failed' }
        if ($null -ne $AutomationCommand) {
            $marker = & $AutomationCommand $url $executionCandidate $output $gui.Id
            if (-not (Test-AutomationCompletion -Marker $marker -GuiProcessId $gui.Id -Url $url -OutputDirectory $output)) { throw 'automation_marker_invalid' }
        }
        elseif ($OperatorGuided) {
            if ((Read-Host "Observe the candidate GUI and complete MP3 download for $url. Type YES after verifying completion") -cne 'YES') { throw 'operator_not_confirmed' }
        }
        else { throw 'automation_required' }
        $probeCapture = [pscustomobject]@{ Text = $null }
        $result = Test-SmokeOutput -OutputDirectory $output -StartedAtUtc $startedAtUtc -FfprobeAction { param($path) $probeCapture.Text = (Invoke-SmokeProcess -ReasonCode 'ffprobe_failed' -Action { (Invoke-CheckedProcess -FilePath (Join-Path $executionCandidate 'ffprobe.exe') -Arguments @('-v', 'error', '-show_entries', 'format=duration:stream=codec_name', '-of', 'default=noprint_wrappers=1', $path) -Name 'smoke ffprobe').StandardOutput }); $probeCapture.Text }
        if (-not $result.Valid) { throw $result.ReasonCode }
        $successEvidenceAction = {
            $finalProbe = (Invoke-SmokeProcess -ReasonCode 'ffprobe_failed' -Action { (Invoke-CheckedProcess -FilePath (Join-Path $executionCandidate 'ffprobe.exe') -Arguments @('-v', 'error', '-show_entries', 'format=duration:stream=codec_name', '-of', 'default=noprint_wrappers=1', $result.Mp3Path) -Name 'final smoke ffprobe').StandardOutput })
            New-SmokeSuccessEvidence -Workspace $workspace -OutputDirectory $output -Mp3Path $result.Mp3Path -SettingsPath (Join-Path $executionCandidate 'ytdlp-interface.json') -FfprobeOutput ([string]$finalProbe) -EvidenceDirectory $evidence -RunId $runId
        }
        $proofEvidence = [ordered]@{ artifactValidated = $true; guiInteractionProven = $false; operatorAttested = ($mode -eq 'operator-guided') }
        $succeeded = $true; $reasonCode = 'ok'; return $result
    }
    catch {
        $known = @('candidate_parent_overlap', 'candidate_missing', 'candidate_manifest_missing', 'candidate_manifest_invalid', 'candidate_manifest_digest_mismatch', 'candidate_manifest_mismatch', 'candidate_copy_mismatch', 'smoke_execution_attestation_invalid', 'smoke_success_evidence_invalid', 'workspace_containment', 'output_not_empty', 'fixture_generation_failed', 'url_rejected', 'python_missing', 'server_not_ready', 'gui_start_failed', 'automation_marker_invalid', 'operator_not_confirmed', 'automation_required', 'output_missing', 'part_file', 'mp3_missing', 'stale_output', 'ffprobe_failed', 'codec_not_mp3', 'duration_invalid')
        if ($known -contains $_.Exception.Message) { $reasonCode = $_.Exception.Message } else { $reasonCode = 'unexpected_failure' }
        throw
    }
    finally { Complete-SmokeRun -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$succeeded -ReasonCode $reasonCode -RunId $runId -Mode $mode -OutputEvidence $outputEvidence -CandidateManifestSha256 $manifestBindingSha256 -ProofEvidence $proofEvidence -ExecutionAttestation $executionAttestation -SuccessEvidenceAction $successEvidenceAction -CleanupAction { Stop-TrackedProcesses -Processes $processes } }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $smokeRun) { Write-Output 'No action taken. Re-run with -Run and either -AutomationCommand or -OperatorGuided.' }
    else { Invoke-LocalhostSmoke -CandidateRoot $CandidateRoot -ParentRuntime $smokeParentRuntime -PythonPath $PythonPath -DownloadsPath $smokeDownloadsPath -ExpectedCandidateManifestSha256 $smokeExpectedCandidateManifestSha256 -OperatorGuided:$OperatorGuided -AutomationCommand $AutomationCommand }
}
