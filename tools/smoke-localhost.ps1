[CmdletBinding()]
param(
    [string] $CandidateRoot,
    [string] $ParentRuntime,
    [switch] $Run,
    [switch] $OperatorGuided,
    [scriptblock] $AutomationCommand
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
    param([object[]] $Processes, [scriptblock] $StopAction = { param($process) Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue })
    foreach ($process in @($Processes)) {
        if ($null -ne $process -and -not $process.HasExited) { & $StopAction $process }
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
    $probe = [string](& $FfprobeAction $mp3.FullName)
    if ($probe -notmatch '(?m)^codec_name=mp3$') { return [pscustomobject]@{ Valid = $false; ReasonCode = 'codec_not_mp3' } }
    $durationMatch = [regex]::Match($probe, '(?m)^duration=([0-9]+(?:\.[0-9]+)?)$')
    if (-not $durationMatch.Success -or [double]$durationMatch.Groups[1].Value -le 0) { return [pscustomobject]@{ Valid = $false; ReasonCode = 'duration_invalid' } }
    return [pscustomobject]@{ Valid = $true; ReasonCode = 'ok'; Mp3Path = $mp3.FullName; Duration = [double]$durationMatch.Groups[1].Value }
}

function Complete-SmokeWorkspace {
    param([string] $Workspace, [string] $EvidenceDirectory, [bool] $Succeeded, [string] $ReasonCode)
    [IO.Directory]::CreateDirectory($EvidenceDirectory) | Out-Null
    $name = if ($Succeeded) { 'result.json' } else { 'failure.json' }
    $manifest = [ordered]@{ succeeded = $Succeeded; reasonCode = $ReasonCode; completedAtUtc = [DateTime]::UtcNow.ToString('o'); workspaceId = (Split-Path -Leaf $Workspace) }
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory $name), ($manifest | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    if ($Succeeded -and (Test-Path -LiteralPath $Workspace)) { Remove-Item -LiteralPath $Workspace -Recurse -Force }
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
    param([string] $CandidateRoot, [string] $ParentRuntime, [switch] $OperatorGuided, [scriptblock] $AutomationCommand)
    if ([string]::IsNullOrWhiteSpace($ParentRuntime)) { throw 'parent_runtime_required' }
    $candidate = [IO.Path]::GetFullPath($CandidateRoot)
    $parent = [IO.Path]::GetFullPath($ParentRuntime)
    if (Test-PathOverlap -First $candidate -Second $parent) { throw 'candidate_parent_overlap' }
    if (-not (Test-Path -LiteralPath (Join-Path $candidate 'ytdlp-interface.exe'))) { throw 'candidate_missing' }
    foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) { if (-not (Test-Path -LiteralPath (Join-Path $candidate $name))) { throw 'candidate_missing' } }
    $workspace = Join-Path $candidate ('smoke-work-' + [Guid]::NewGuid().ToString('N'))
    $output = Join-Path $workspace 'output'
    $evidence = Join-Path $candidate 'smoke-evidence'
    if (-not (Test-PathContained -Root $workspace -Path $output) -or (Test-PathOverlap -First $parent -Second $workspace) -or (Test-PathOverlap -First $parent -Second $evidence)) { throw 'workspace_containment' }
    [IO.Directory]::CreateDirectory($workspace) | Out-Null
    [IO.Directory]::CreateDirectory($output) | Out-Null
    if (@(Get-ChildItem -LiteralPath $output -Force).Count -ne 0) { throw 'output_not_empty' }
    $processes = @(); $succeeded = $false; $reasonCode = 'smoke_failed'
    try {
        $media = Join-Path $workspace 'input.mp4'
        & (Join-Path $candidate 'ffmpeg.exe') '-y' '-f' 'lavfi' '-i' 'sine=frequency=1000:duration=2' '-t' '2' $media
        if ($LASTEXITCODE -ne 0) { throw 'fixture_generation_failed' }
        $port = Get-LoopbackPort
        $url = "http://127.0.0.1:$port/input.mp4"
        if (-not (Test-LocalhostUrl -Url $url)) { throw 'url_rejected' }
        $python = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $python) { throw 'python_missing' }
        $server = Start-Process -FilePath $python.Source -ArgumentList @('-m', 'http.server', $port, '--bind', '127.0.0.1', '--directory', $workspace) -PassThru -RedirectStandardOutput (Join-Path $workspace 'server.out') -RedirectStandardError (Join-Path $workspace 'server.err')
        $processes += $server
        Wait-LoopbackServer -Url $url
        $startedAtUtc = [DateTime]::UtcNow
        $gui = Start-Process -FilePath (Join-Path $candidate 'ytdlp-interface.exe') -WorkingDirectory $candidate -PassThru
        $processes += $gui
        Start-Sleep -Seconds 1; $gui.Refresh()
        if ($gui.HasExited) { throw 'gui_start_failed' }
        if ($null -ne $AutomationCommand) {
            $marker = & $AutomationCommand $url $candidate $output $gui.Id
            if (-not (Test-AutomationCompletion -Marker $marker -GuiProcessId $gui.Id -Url $url -OutputDirectory $output)) { throw 'automation_marker_invalid' }
        }
        elseif ($OperatorGuided) {
            if ((Read-Host "Observe the candidate GUI and complete MP3 download for $url. Type YES after verifying completion") -cne 'YES') { throw 'operator_not_confirmed' }
        }
        else { throw 'automation_required' }
        $result = Test-SmokeOutput -OutputDirectory $output -StartedAtUtc $startedAtUtc -FfprobeAction { param($path) & (Join-Path $candidate 'ffprobe.exe') '-v' 'error' '-show_entries' 'format=duration:stream=codec_name' '-of' 'default=noprint_wrappers=1' $path }
        if (-not $result.Valid) { throw $result.ReasonCode }
        $succeeded = $true; $reasonCode = 'ok'; return $result
    }
    catch {
        $known = @('candidate_parent_overlap', 'candidate_missing', 'workspace_containment', 'output_not_empty', 'fixture_generation_failed', 'url_rejected', 'python_missing', 'server_not_ready', 'gui_start_failed', 'automation_marker_invalid', 'operator_not_confirmed', 'automation_required', 'output_missing', 'part_file', 'mp3_missing', 'stale_output', 'codec_not_mp3', 'duration_invalid')
        if ($known -contains $_.Exception.Message) { $reasonCode = $_.Exception.Message } else { $reasonCode = 'unexpected_failure' }
        throw
    }
    finally { Stop-TrackedProcesses -Processes $processes; Complete-SmokeWorkspace -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$succeeded -ReasonCode $reasonCode }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Run) { Write-Output 'No action taken. Re-run with -Run and either -AutomationCommand or -OperatorGuided.' }
    else { Invoke-LocalhostSmoke -CandidateRoot $CandidateRoot -ParentRuntime $ParentRuntime -OperatorGuided:$OperatorGuided -AutomationCommand $AutomationCommand }
}
