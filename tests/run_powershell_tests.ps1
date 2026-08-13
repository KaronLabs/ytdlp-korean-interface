$ErrorActionPreference = 'Stop'
foreach ($testPath in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'powershell') -Filter '*.Tests.ps1' | Sort-Object Name)) {
    Write-Output ("START " + $testPath.Name)
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $testPath.FullName
    if ($LASTEXITCODE -ne 0) { Write-Error ("FAIL " + $testPath.Name); exit $LASTEXITCODE }
    Write-Output ("PASS " + $testPath.Name)
}
