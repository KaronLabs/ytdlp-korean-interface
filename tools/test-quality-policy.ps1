[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $EvidenceRoot,
    [switch] $ImplementationReady
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $ImplementationReady) { throw 'A-ready/controller signal required before production validation.' }
$sourceRoot = Split-Path -Parent $PSScriptRoot
$evidence = [IO.Path]::GetFullPath($EvidenceRoot)
if (Test-Path -LiteralPath $evidence) { throw 'EvidenceRoot must be a new directory.' }
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if (-not $installation) { throw 'MSVC v143 toolchain not found.' }
$msbuild = Join-Path $installation 'MSBuild/Current/Bin/MSBuild.exe'
$project = Join-Path $sourceRoot 'tests/native/quality_policy_tests.vcxproj'
$header = Join-Path $sourceRoot 'ytdlp-interface/download_policy.hpp'
$before = (Get-FileHash -LiteralPath $header -Algorithm SHA256).Hash
$buildArgs = @($project, '/t:Build', '/p:Configuration=Release', '/p:Platform=x64', ('/p:OutDir=' + $evidence + '/bin/'), ('/p:IntDir=' + $evidence + '/obj/'), '/v:minimal', '/nologo')
$record = [ordered]@{ tier = 'PRODUCTION_HELPER'; guiAcceptance = $false; startedUtc = [DateTime]::UtcNow.ToString('o'); headerSha256 = $before; executable = $msbuild; arguments = $buildArgs }
& $msbuild @buildArgs *> (Join-Path $evidence 'build.log')
$record.buildExit = $LASTEXITCODE
if ($record.buildExit -eq 0) {
    $native = Join-Path $evidence 'bin/quality_policy_tests.exe'
    & $native *> (Join-Path $evidence 'tests.log')
    $record.testsExit = $LASTEXITCODE
    $record.testExecutableSha256 = (Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash
}
$record.headerUnchanged = $before -eq (Get-FileHash -LiteralPath $header -Algorithm SHA256).Hash
$record.finishedUtc = [DateTime]::UtcNow.ToString('o')
$record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'result.json') -Encoding UTF8
if ($record.buildExit -ne 0 -or -not $record.headerUnchanged -or $record.testsExit -ne 0) {
    throw ('Production helper validation failed; inspect ' + $evidence)
}
Get-Content -LiteralPath (Join-Path $evidence 'tests.log')
Write-Output ('Helper=' + $native)
