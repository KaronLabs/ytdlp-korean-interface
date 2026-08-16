[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $StatusPath,
    [Parameter(Mandatory = $true)] [string] $StdoutPath,
    [Parameter(Mandatory = $true)] [string] $StderrPath
)
$ErrorActionPreference = 'Stop'
$pythonPath = 'C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$serverScript = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\hls-subtitle-server-candidate7.py'
$startedAtUtc = [DateTime]::UtcNow.ToString('o')
$process = Start-Process -FilePath $pythonPath -ArgumentList @($serverScript) -WindowStyle Hidden -RedirectStandardOutput ([IO.Path]::GetFullPath($StdoutPath)) -RedirectStandardError ([IO.Path]::GetFullPath($StderrPath)) -PassThru
Start-Sleep -Milliseconds 500
[ordered]@{
    schemaVersion = 1
    startedAtUtc = $startedAtUtc
    pid = $process.Id
    url = 'http://127.0.0.1:60324/master.m3u8'
    pythonPath = $pythonPath
    serverScript = $serverScript
    stdoutPath = [IO.Path]::GetFullPath($StdoutPath)
    stderrPath = [IO.Path]::GetFullPath($StderrPath)
    aliveAfterStart = -not $process.HasExited
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ([IO.Path]::GetFullPath($StatusPath)) -Encoding UTF8
