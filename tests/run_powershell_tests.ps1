$ErrorActionPreference = 'Stop'
foreach ($testPath in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'powershell') -Filter '*.Tests.ps1' | Sort-Object Name)) {
    & $testPath.FullName
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
