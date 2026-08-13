$ErrorActionPreference = 'Stop'
$sourceRoot = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src'
Set-Location -LiteralPath $sourceRoot
. .\tools\smoke-localhost.ps1

$evidenceCandidateRoot = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-candidates\candidate-dc08eec8638f433b835ce6a5520499b1'
$evidenceParentRuntime = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface'
$evidencePythonPath = 'C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$automation = {
    param($url, $executionCandidate, $outputDirectory, $guiProcessId)
    Invoke-CheckedProcess -FilePath (Join-Path $executionCandidate 'yt-dlp.exe') -Arguments @('--no-playlist', '--extract-audio', '--audio-format', 'mp3', '--output', (Join-Path $outputDirectory 'artifact.%(ext)s'), $url) -Name 'artifact-only localhost extraction' | Out-Null
    [pscustomobject]@{ Completed = $true; GuiProcessId = $guiProcessId; Url = $url; OutputDirectory = $outputDirectory }
}

"STARTED_AT_UTC=$([DateTime]::UtcNow.ToString('o'))"
"CANDIDATE_ROOT=$evidenceCandidateRoot"
"CANDIDATE_MANIFEST_SHA256=$((Get-FileHash -LiteralPath (Join-Path $evidenceCandidateRoot 'candidate-manifest.json') -Algorithm SHA256).Hash.ToUpperInvariant())"
$result = Invoke-LocalhostSmoke -CandidateRoot $evidenceCandidateRoot -ParentRuntime $evidenceParentRuntime -PythonPath $evidencePythonPath -AutomationCommand $automation
$result | ConvertTo-Json -Compress
"COMPLETED_AT_UTC=$([DateTime]::UtcNow.ToString('o'))"
