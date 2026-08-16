[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $StatusPath,
    [Parameter(Mandatory = $true)] [string] $ArtifactPath
)
$ErrorActionPreference = 'Stop'
$startedAtUtc = [DateTime]::UtcNow.ToString('o')
$exitCode = 1
$exception = $null
$sourceRoot = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src'
$successorCandidateRoot = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-5\candidate-55e66fa7d6004a0c84bce001c97d2c4d'
$smokeParentRuntimePinned = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface'
$smokePythonPathPinned = 'C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$successorManifestPath = Join-Path $successorCandidateRoot 'candidate-manifest.json'
$expected = (Get-FileHash -LiteralPath $successorManifestPath -Algorithm SHA256).Hash.ToUpperInvariant()
try {
    Set-Location -LiteralPath $sourceRoot
    . .\tools\smoke-localhost.ps1
    $automation = {
        param($url, $executionCandidate, $outputDirectory, $guiProcessId)
        Invoke-CheckedProcess -FilePath (Join-Path $executionCandidate 'yt-dlp.exe') -Arguments @('--no-playlist','--extract-audio','--audio-format','mp3','--output',(Join-Path $outputDirectory 'artifact.%(ext)s'),$url) -Name 'artifact-only localhost extraction' | Out-Null
        $mp3 = Get-ChildItem -LiteralPath $outputDirectory -Filter '*.mp3' -File | Select-Object -First 1
        if ($null -eq $mp3) { throw 'artifact_copy_missing' }
        [pscustomobject]@{ Completed = $true; GuiProcessId = $guiProcessId; Url = $url; OutputDirectory = $outputDirectory }
    }
    "STARTED_AT_UTC=$startedAtUtc"
    "CANDIDATE_ROOT=$successorCandidateRoot"
    "CANDIDATE_MANIFEST_SHA256=$expected"
    $result = Invoke-LocalhostSmoke -CandidateRoot $successorCandidateRoot -ParentRuntime $smokeParentRuntimePinned -PythonPath $smokePythonPathPinned -DownloadsPath 'C:\Users\ceo\Downloads' -ExpectedCandidateManifestSha256 $expected -AutomationCommand $automation
    $result | ConvertTo-Json -Compress
    $exitCode = 0
}
catch { $exception = $_.Exception.ToString(); throw }
finally {
    [ordered]@{ schemaVersion=1; startedAtUtc=$startedAtUtc; completedAtUtc=[DateTime]::UtcNow.ToString('o'); candidateRoot=$successorCandidateRoot; expectedManifestSha256=$expected; artifactPath=$ArtifactPath; exitCode=$exitCode; exception=$exception } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ([IO.Path]::GetFullPath($StatusPath)) -Encoding UTF8
}
