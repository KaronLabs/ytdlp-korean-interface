$ErrorActionPreference = 'Stop'
foreach ($testPath in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'powershell') -Filter '*.Tests.ps1' | Sort-Object Name)) {
    Write-Output ("START " + $testPath.Name)
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $testPath.FullName.Replace('"', '\"') + '"'))
    $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) { Write-Error ("FAIL " + $testPath.Name); exit $process.ExitCode }
    Write-Output ("PASS " + $testPath.Name)
}
