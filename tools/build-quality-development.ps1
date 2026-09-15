[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $EvidenceRoot,
    [string] $ExistingSnapshot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$validationSource = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$validationRoot = [IO.Path]::GetFullPath($EvidenceRoot)
if ($validationRoot.StartsWith($validationSource.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $validationRoot -eq $validationSource) {
    throw 'Development build evidence must be outside the worktree.'
}
if (Test-Path -LiteralPath $validationRoot) { throw 'EvidenceRoot must be a new directory.' }
[IO.Directory]::CreateDirectory($validationRoot) | Out-Null
$validationSnapshot = if ($ExistingSnapshot) { [IO.Path]::GetFullPath($ExistingSnapshot) } else { Join-Path $validationRoot 'source' }
if ($validationSnapshot.StartsWith($validationSource.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $validationSnapshot -eq $validationSource) {
    throw 'Existing snapshot must be outside the worktree.'
}
[IO.Directory]::CreateDirectory($validationSnapshot) | Out-Null
. (Join-Path $PSScriptRoot 'build-candidate.ps1')
$validationSummary = [ordered]@{
    tier = 'UNSEALED_FULL_APPLICATION_DEVELOPMENT_BUILD'
    sourceRoot = $validationSource
    snapshotRoot = $validationSnapshot
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    sealed = $false
    guiAcceptance = $false
    succeeded = $false
}

function Invoke-QualityBuildStep {
    param([string] $Step, [string] $Executable, [string[]] $StepArguments, [object] $Context)
    $record = [ordered]@{ step = $Step; executable = $Executable; arguments = $StepArguments; startedAtUtc = [DateTime]::UtcNow.ToString('o'); cwd = $Context.WorkingDirectory }
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $validationRoot 'current-step.json') -Encoding UTF8
    Write-Output ('START ' + $Step)
    try {
        $result = Invoke-CheckedProcess -FilePath $Executable -Arguments $StepArguments -Name $Step -NormalizeEnvironment -WorkingDirectory $Context.WorkingDirectory -EnvironmentOverrides $Context.EnvironmentOverrides
        $record.exitCode = $result.ExitCode
        $result.StandardOutput | Set-Content -LiteralPath (Join-Path $validationRoot ($Step + '.stdout.log')) -Encoding UTF8
        $result.StandardError | Set-Content -LiteralPath (Join-Path $validationRoot ($Step + '.stderr.log')) -Encoding UTF8
    }
    catch {
        $record.error = $_.Exception.Message
        if ($record.error -match 'exited with code ([0-9]+)') { $record.exitCode = [int]$Matches[1] }
        $record.error | Set-Content -LiteralPath (Join-Path $validationRoot ($Step + '.error.log')) -Encoding UTF8
        throw ('Build step failed: ' + $Step + '. See raw log in ' + $validationRoot)
    }
    finally {
        $record.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
        $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $validationRoot ($Step + '.command.json')) -Encoding UTF8
    }
    Write-Output ('PASS ' + $Step)
}

try {
    if (-not $ExistingSnapshot) {
        foreach ($folder in @('ytdlp-interface', 'locales', 'tests')) {
            Copy-Item -LiteralPath (Join-Path $validationSource $folder) -Destination (Join-Path $validationSnapshot $folder) -Recurse
        }
        [IO.Directory]::CreateDirectory((Join-Path $validationSnapshot 'tools')) | Out-Null
        Copy-Item -LiteralPath (Join-Path $validationSource 'tools/dependency-archives.json') -Destination (Join-Path $validationSnapshot 'tools/dependency-archives.json')
    }
    if ($ExistingSnapshot -and -not (Test-Path -LiteralPath (Join-Path $validationSnapshot 'tests/native/i18n_tests.vcxproj'))) {
        Copy-Item -LiteralPath (Join-Path $validationSource 'tests') -Destination (Join-Path $validationSnapshot 'tests') -Recurse
    }
    $snapshotFiles = @(Get-ChildItem -LiteralPath (Join-Path $validationSnapshot 'ytdlp-interface'), (Join-Path $validationSnapshot 'locales'), (Join-Path $validationSnapshot 'tests') -Recurse -File | ForEach-Object {
        [ordered]@{ path = $_.FullName.Substring($validationSnapshot.Length).TrimStart('\', '/'); length = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    $snapshotFiles | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $validationRoot 'source-snapshot.json') -Encoding UTF8
    $validationSummary.headerSha256 = (Get-FileHash -LiteralPath (Join-Path $validationSnapshot 'ytdlp-interface/download_policy.hpp') -Algorithm SHA256).Hash
    Write-Output 'START verified dependency archive extraction'
    Initialize-OfficialDependencies -SourceRoot $validationSnapshot -DependencyArchiveDirectory $validationSource
    Write-Output 'PASS verified dependency archive extraction'
    $buildTools = Get-VsBuildTools
    $cmakeExecutable = Get-CmakeExecutable -VisualStudioInstallation $buildTools.InstallationPath
    $buildTools | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $validationRoot 'toolchain.json') -Encoding UTF8
    $context = New-HermeticBuildContext -SourceRoot $validationSnapshot -WorkspaceRoot $validationRoot -VCToolsVersion $buildTools.VCToolsVersion -WindowsSdkVersion $buildTools.WindowsSdkVersion
    if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') { throw 'This development runner requires an x64 Windows host.' }
    $context.EnvironmentOverrides['PROCESSOR_ARCHITECTURE'] = 'AMD64'
    $validationSummary.environmentOverrides = $context.EnvironmentOverrides
    $dependencyPlan = Get-ReleaseX64DependencyPlan -SourceRoot $validationSnapshot -MsBuildPath $buildTools.MsBuildPath -CmakePath $cmakeExecutable -CommonMsBuildArguments $context.MsBuildArguments -CmakeVsGlobalsArgument $context.CmakeVsGlobalsArgument
    foreach ($dependency in $dependencyPlan) {
        if ($ExistingSnapshot -and (Test-Path -LiteralPath $dependency.LibraryPath -PathType Leaf)) {
            Write-Output ('REUSE ' + $dependency.Name + ' previously built library')
            continue
        }
        if ($dependency.Name -eq 'libjpeg-turbo') { $dependency.Arguments = @('--fresh') + @($dependency.Arguments) }
        Invoke-QualityBuildStep -Step $dependency.Name -Executable $dependency.FilePath -StepArguments $dependency.Arguments -Context $context
        if ($dependency.BuildArguments.Count) {
            Invoke-QualityBuildStep -Step ($dependency.Name + '-build') -Executable $dependency.FilePath -StepArguments $dependency.BuildArguments -Context $context
        }
        if (-not (Test-Path -LiteralPath $dependency.LibraryPath -PathType Leaf)) { throw ('Dependency library missing: ' + $dependency.LibraryPath) }
    }
    $productArguments = @((Join-Path $validationSnapshot 'ytdlp-interface/ytdlp-interface.sln'), '/m', '/t:Build') + @($context.MsBuildArguments)
    Invoke-QualityBuildStep -Step 'whole-application' -Executable $buildTools.MsBuildPath -StepArguments $productArguments -Context $context
    $productPath = Join-Path $validationSnapshot 'ytdlp-interface/x64/Release/ytdlp-interface.exe'
    if (-not (Test-Path -LiteralPath $productPath -PathType Leaf)) { throw 'Application EXE missing after successful build.' }
    $validationSummary.productPath = $productPath
    $validationSummary.productSha256 = (Get-FileHash -LiteralPath $productPath -Algorithm SHA256).Hash
    $validationSummary.succeeded = $true
}
catch {
    $validationSummary.error = $_.Exception.Message
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $validationRoot 'failure.log') -Encoding UTF8
    throw
}
finally {
    $validationSummary.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    $validationSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $validationRoot 'result.json') -Encoding UTF8
}
$validationSummary | ConvertTo-Json -Depth 8
