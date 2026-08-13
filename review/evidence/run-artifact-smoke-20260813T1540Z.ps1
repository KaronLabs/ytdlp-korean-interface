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
$evidenceCandidateRoot = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-candidates\candidate-dc08eec8638f433b835ce6a5520499b1'
$evidenceParentRuntime = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface'
$evidencePythonPath = 'C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'

try {
    Set-Location -LiteralPath $sourceRoot
    . .\tools\smoke-localhost.ps1
    $automation = {
        param($url, $executionCandidate, $outputDirectory, $guiProcessId)
        Invoke-CheckedProcess -FilePath (Join-Path $executionCandidate 'yt-dlp.exe') -Arguments @('--no-playlist', '--extract-audio', '--audio-format', 'mp3', '--output', (Join-Path $outputDirectory 'artifact.%(ext)s'), $url) -Name 'artifact-only localhost extraction' | Out-Null
        $mp3 = Get-ChildItem -LiteralPath $outputDirectory -Filter '*.mp3' -File | Select-Object -First 1
        if ($null -eq $mp3) { throw 'artifact_copy_missing' }
        Copy-Item -LiteralPath $mp3.FullName -Destination $ArtifactPath
        [pscustomobject]@{ Completed = $true; GuiProcessId = $guiProcessId; Url = $url; OutputDirectory = $outputDirectory }
    }
    "STARTED_AT_UTC=$startedAtUtc"
    "CANDIDATE_ROOT=$evidenceCandidateRoot"
    "CANDIDATE_MANIFEST_SHA256=$((Get-FileHash -LiteralPath (Join-Path $evidenceCandidateRoot 'candidate-manifest.json') -Algorithm SHA256).Hash.ToUpperInvariant())"
    $result = Invoke-LocalhostSmoke -CandidateRoot $evidenceCandidateRoot -ParentRuntime $evidenceParentRuntime -PythonPath $evidencePythonPath -AutomationCommand $automation
    $result | ConvertTo-Json -Compress
    "ARTIFACT_SHA256=$((Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToUpperInvariant())"
    "ARTIFACT_LENGTH=$((Get-Item -LiteralPath $ArtifactPath).Length)"
    $exitCode = 0
}
catch {
    $exception = $_.Exception.ToString()
    throw
}
finally {
    [ordered]@{
        schemaVersion = 1
        startedAtUtc = $startedAtUtc
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        command = $MyInvocation.Line
        candidateRoot = $evidenceCandidateRoot
        artifactPath = $ArtifactPath
        exitCode = $exitCode
        exception = $exception
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatusPath -Encoding UTF8
}
