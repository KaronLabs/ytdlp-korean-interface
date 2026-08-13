$ErrorActionPreference = 'Stop'
$testPath = Join-Path $PSScriptRoot 'powershell/runtime-maintenance.Tests.ps1'
& $testPath
exit $LASTEXITCODE
