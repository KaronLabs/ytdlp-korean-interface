$ErrorActionPreference = 'Stop'
foreach ($testPath in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'powershell') -Filter '*.Tests.ps1' | Sort-Object Name)) {
    Write-Output ("START " + $testPath.Name)
    $requiresPwsh = Select-String -LiteralPath $testPath.FullName -Pattern '^\s*#requires\s+-Version\s+7(?:\.|\s|$)' -Quiet
    $hostPath = if ($requiresPwsh) {
        (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop).Source
    }
    else {
        Join-Path $PSHOME 'powershell.exe'
    }
    & $hostPath -NoProfile -ExecutionPolicy Bypass -File $testPath.FullName
    if ($LASTEXITCODE -ne 0) { Write-Error ("FAIL " + $testPath.Name); exit $LASTEXITCODE }
    Write-Output ("PASS " + $testPath.Name)
}
