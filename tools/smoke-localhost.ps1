[CmdletBinding()]
param(
    [string] $CandidateRoot,
    [string] $OutputDirectory,
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
    return $uri.Scheme -eq 'http' -and $uri.Host -eq '127.0.0.1' -and $uri.Port -gt 0
}

function Stop-TrackedProcesses {
    param([object[]] $Processes, [scriptblock] $StopAction = { param($process) Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue })
    foreach ($process in @($Processes)) {
        if ($null -ne $process -and -not $process.HasExited) { & $StopAction $process }
    }
}

function Test-SmokeOutput {
    param([Parameter(Mandatory = $true)] [string] $OutputDirectory, [Parameter(Mandatory = $true)] [scriptblock] $FfprobeAction)
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { return [pscustomobject]@{ Valid = $false; Reason = 'output directory missing' } }
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File -Filter '*.part').Count -ne 0) { return [pscustomobject]@{ Valid = $false; Reason = 'part file remains' } }
    $mp3 = @(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File -Filter '*.mp3' | Where-Object { $_.Length -gt 0 }) | Select-Object -First 1
    if ($null -eq $mp3) { return [pscustomobject]@{ Valid = $false; Reason = 'final MP3 missing or empty' } }
    $probe = [string](& $FfprobeAction $mp3.FullName)
    if ($probe -notmatch '(?m)^codec_name=mp3$') { return [pscustomobject]@{ Valid = $false; Reason = 'ffprobe codec is not mp3' } }
    $durationMatch = [regex]::Match($probe, '(?m)^duration=([0-9]+(?:\.[0-9]+)?)$')
    if (-not $durationMatch.Success -or [double]$durationMatch.Groups[1].Value -le 0) { return [pscustomobject]@{ Valid = $false; Reason = 'ffprobe duration is not positive' } }
    return [pscustomobject]@{ Valid = $true; Reason = $null; Mp3Path = $mp3.FullName; Duration = [double]$durationMatch.Groups[1].Value }
}

function Complete-SmokeWorkspace {
    param([string] $Workspace, [string] $EvidenceDirectory, [bool] $Succeeded, [string] $Reason)
    [IO.Directory]::CreateDirectory($EvidenceDirectory) | Out-Null
    $name = if ($Succeeded) { 'result.json' } else { 'failure.json' }
    $manifest = [ordered]@{ succeeded = $Succeeded; reason = $Reason; completedAtUtc = [DateTime]::UtcNow.ToString('o'); workspace = $Workspace }
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory $name), ($manifest | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    if ($Succeeded -and (Test-Path -LiteralPath $Workspace)) { Remove-Item -LiteralPath $Workspace -Recurse -Force }
}

function Get-LoopbackPort {
    $listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Parse('127.0.0.1')), 0
    try { $listener.Start(); return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Invoke-LocalhostSmoke {
    param([string] $CandidateRoot, [string] $OutputDirectory, [switch] $OperatorGuided, [scriptblock] $AutomationCommand)
    $candidate = [IO.Path]::GetFullPath($CandidateRoot)
    if (-not (Test-Path -LiteralPath (Join-Path $candidate 'ytdlp-interface.exe'))) { throw 'Candidate GUI is missing.' }
    foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) { if (-not (Test-Path -LiteralPath (Join-Path $candidate $name))) { throw "Candidate is missing $name." } }
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $candidate ('smoke-output-' + [Guid]::NewGuid().ToString('N')) }
    $output = [IO.Path]::GetFullPath($OutputDirectory)
    if (-not (Test-PathContained -Root $candidate -Path $output)) { throw 'Smoke output must remain inside the candidate directory.' }
    $workspace = Join-Path $candidate ('smoke-work-' + [Guid]::NewGuid().ToString('N'))
    $evidence = Join-Path $candidate 'smoke-evidence'
    [IO.Directory]::CreateDirectory($workspace) | Out-Null
    [IO.Directory]::CreateDirectory($output) | Out-Null
    $processes = @(); $succeeded = $false; $reason = 'smoke did not complete'
    try {
        $media = Join-Path $workspace 'input.mp4'
        & (Join-Path $candidate 'ffmpeg.exe') '-y' '-f' 'lavfi' '-i' 'sine=frequency=1000:duration=2' '-t' '2' $media
        if ($LASTEXITCODE -ne 0) { throw 'ffmpeg could not generate the two-second fixture.' }
        $port = Get-LoopbackPort
        $url = "http://127.0.0.1:$port/input.mp4"
        if (-not (Test-LocalhostUrl -Url $url)) { throw 'Smoke URL failed the localhost-only guard.' }
        $python = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $python) { throw 'python.exe is required only to serve the local fixture.' }
        $serverOut = Join-Path $workspace 'server.out'; $serverErr = Join-Path $workspace 'server.err'
        $server = Start-Process -FilePath $python.Source -ArgumentList @('-m', 'http.server', $port, '--bind', '127.0.0.1', '--directory', $workspace) -PassThru -RedirectStandardOutput $serverOut -RedirectStandardError $serverErr
        $processes += $server
        $gui = Start-Process -FilePath (Join-Path $candidate 'ytdlp-interface.exe') -WorkingDirectory $candidate -PassThru
        $processes += $gui
        if ($null -ne $AutomationCommand) { & $AutomationCommand $url $candidate $output }
        elseif ($OperatorGuided) { Read-Host "In the candidate GUI choose Korean, download only $url as MP3 into $output, then press Enter" | Out-Null }
        else { throw 'Specify -AutomationCommand or -OperatorGuided; the script never invents GUI actions.' }
        $result = Test-SmokeOutput -OutputDirectory $output -FfprobeAction { param($path) & (Join-Path $candidate 'ffprobe.exe') '-v' 'error' '-show_entries' 'format=duration:stream=codec_name' '-of' 'default=noprint_wrappers=1' $path }
        if (-not $result.Valid) { throw $result.Reason }
        $succeeded = $true; $reason = 'localhost MP3 smoke passed'
        return $result
    }
    catch { $reason = $_.Exception.Message; throw }
    finally {
        Stop-TrackedProcesses -Processes $processes
        Complete-SmokeWorkspace -Workspace $workspace -EvidenceDirectory $evidence -Succeeded:$succeeded -Reason $reason
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Run) { Write-Output 'No action taken. Re-run with -Run and either -AutomationCommand or -OperatorGuided.' }
    else { Invoke-LocalhostSmoke -CandidateRoot $CandidateRoot -OutputDirectory $OutputDirectory -OperatorGuided:$OperatorGuided -AutomationCommand $AutomationCommand }
}
