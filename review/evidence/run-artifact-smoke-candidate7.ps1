[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $StatusPath
)
$ErrorActionPreference = 'Stop'
$startedAtUtc = [DateTime]::UtcNow.ToString('o')
$exitCode = 1
$exception = $null
$sourceRoot = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src'
$sealedCandidateRoot = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-7\candidate-40b53764d6d244858b9e5b4ead6dbad1'
$sealedParentRuntime = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface'
$sealedPythonPath = 'C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$sealedManifestPath = Join-Path $sealedCandidateRoot 'candidate-manifest.json'
$expected = (Get-FileHash -LiteralPath $sealedManifestPath -Algorithm SHA256).Hash.ToUpperInvariant()
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
    "CANDIDATE_ROOT=$sealedCandidateRoot"
    "CANDIDATE_MANIFEST_SHA256=$expected"
    $result = Invoke-LocalhostSmoke -CandidateRoot $sealedCandidateRoot -ParentRuntime $sealedParentRuntime -PythonPath $sealedPythonPath -DownloadsPath 'C:\Users\ceo\Downloads' -ExpectedCandidateManifestSha256 $expected -AutomationCommand $automation
    $result | ConvertTo-Json -Compress
    $exitCode = 0
}
catch { $exception = $_.Exception.ToString(); throw }
finally {
    [ordered]@{ schemaVersion=1; startedAtUtc=$startedAtUtc; completedAtUtc=[DateTime]::UtcNow.ToString('o'); candidateRoot=$sealedCandidateRoot; expectedManifestSha256=$expected; exitCode=$exitCode; exception=$exception } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ([IO.Path]::GetFullPath($StatusPath)) -Encoding UTF8
}
