[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $SourceRoot,
    [Parameter(Mandatory = $true)] [string] $ParentRuntime,
    [Parameter(Mandatory = $true)] [string] $CandidateBase,
    [Parameter(Mandatory = $true)] [string] $DependencyArchiveDirectory,
    [Parameter(Mandatory = $true)] [string] $StatusPath
)

$ErrorActionPreference = 'Stop'
$startedAtUtc = [DateTime]::UtcNow.ToString('o')
$exitCode = 1
$exception = $null
$buildScript = Join-Path $SourceRoot 'tools\build-candidate.ps1'
$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $buildScript, '-Run', '-SourceRoot', $SourceRoot, '-ParentRuntime', $ParentRuntime, '-CandidateBase', $CandidateBase, '-DependencyArchiveDirectory', $DependencyArchiveDirectory)

try {
    & powershell.exe @arguments
    $exitCode = $LASTEXITCODE
}
catch {
    $exception = $_.Exception.ToString()
}

[ordered]@{
    schemaVersion = 1
    startedAtUtc = $startedAtUtc
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    executable = 'powershell.exe'
    arguments = $arguments
    exitCode = $exitCode
    exception = $exception
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatusPath -Encoding UTF8

exit $exitCode
