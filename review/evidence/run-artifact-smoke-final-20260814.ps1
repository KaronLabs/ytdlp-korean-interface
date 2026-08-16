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
$freshCandidateRoot = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-4\candidate-2ccc31fd803f47179fe7487f5f084b93'
$freshParentRuntime = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface'
$freshPythonPath = 'C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$manifestPath = Join-Path $freshCandidateRoot 'candidate-manifest.json'
$expectedManifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToUpperInvariant()

try {
    Set-Location -LiteralPath $sourceRoot
    . .\tools\smoke-localhost.ps1
    $automation = {
        param($url, $executionCandidate, $outputDirectory, $guiProcessId)
        Invoke-CheckedProcess -FilePath (Join-Path $executionCandidate 'yt-dlp.exe') -Arguments @('--no-playlist', '--extract-audio', '--audio-format', 'mp3', '--output', (Join-Path $outputDirectory 'artifact.%(ext)s'), $url) -Name 'artifact-only localhost extraction' | Out-Null
        $mp3 = Get-ChildItem -LiteralPath $outputDirectory -Filter '*.mp3' -File | Select-Object -First 1
        if ($null -eq $mp3) { throw 'artifact_copy_missing' }
        [pscustomobject]@{ Completed = $true; GuiProcessId = $guiProcessId; Url = $url; OutputDirectory = $outputDirectory }
    }
    "STARTED_AT_UTC=$startedAtUtc"
    "CANDIDATE_ROOT=$freshCandidateRoot"
    "CANDIDATE_MANIFEST_SHA256=$expectedManifestSha256"
    $result = Invoke-LocalhostSmoke -CandidateRoot $freshCandidateRoot -ParentRuntime $freshParentRuntime -PythonPath $freshPythonPath -DownloadsPath 'C:\Users\ceo\Downloads' -ExpectedCandidateManifestSha256 $expectedManifestSha256 -AutomationCommand $automation
    $result | ConvertTo-Json -Compress
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
        candidateRoot = $freshCandidateRoot
        expectedCandidateManifestSha256 = $expectedManifestSha256
        artifactPath = $ArtifactPath
        exitCode = $exitCode
        exception = $exception
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatusPath -Encoding UTF8
}
