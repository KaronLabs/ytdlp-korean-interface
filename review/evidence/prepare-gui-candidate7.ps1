[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $EvidencePath
)
$ErrorActionPreference = 'Stop'
$sourceRoot = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src'
$candidate = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-7\candidate-40b53764d6d244858b9e5b4ead6dbad1'
$manifestPath = Join-Path $candidate 'candidate-manifest.json'
$baseHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToUpperInvariant()
$workspace = Join-Path ([IO.Path]::GetTempPath()) ('ytdlp-interface-gui-candidate7-' + [Guid]::NewGuid().ToString('N'))
$started = [DateTime]::UtcNow.ToString('o')
Set-Location -LiteralPath $sourceRoot
. .\tools\smoke-localhost.ps1
$execution = Copy-SealedCandidateForSmoke -CandidateRoot $candidate -Workspace $workspace -ExpectedCandidateManifestSha256 $baseHash
$output = Join-Path $workspace 'output'
[IO.Directory]::CreateDirectory($output) | Out-Null
Set-SmokeCandidateOutputPath -CandidateRoot $execution -OutputDirectory $output
$attestation = Assert-SmokeExecutionOverlay -ExecutionCandidate $execution -BaseCandidateRoot $candidate -BaseCandidateManifestSha256 $baseHash -ExpectedOutputDirectory $output -Phase 'pre-run'
$result = [ordered]@{
    schemaVersion = 1
    startedAtUtc = $started
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    baseCandidateRoot = $candidate
    executionRoot = $execution
    outputDirectory = $output
    baseManifestSha256 = $baseHash
    attestation = $attestation
}
$full = [IO.Path]::GetFullPath($EvidencePath)
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $full -Encoding UTF8
$result | ConvertTo-Json -Depth 20
