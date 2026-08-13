[CmdletBinding()]
param(
    [string] $SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $ParentRuntime,
    [string] $CandidateBase,
    [string] $DependencyArchiveDirectory,
    [switch] $Run
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PathContained {
    param([Parameter(Mandatory = $true)] [string] $Root, [Parameter(Mandatory = $true)] [string] $Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $pathFull = [IO.Path]::GetFullPath($Path)
    return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function New-CandidateRoot {
    param([Parameter(Mandatory = $true)] [string] $BaseDirectory)
    $baseFull = [IO.Path]::GetFullPath($BaseDirectory)
    [IO.Directory]::CreateDirectory($baseFull) | Out-Null
    do { $candidate = Join-Path $baseFull ('candidate-' + [Guid]::NewGuid().ToString('N')) } while (Test-Path -LiteralPath $candidate)
    if (-not (Test-PathContained -Root $baseFull -Path $candidate)) { throw 'Candidate path escaped its configured base directory.' }
    [IO.Directory]::CreateDirectory($candidate) | Out-Null
    return $candidate
}

function Get-VsBuildTools {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }
    $vswhere = $candidates | Select-Object -First 1
    if ($null -eq $vswhere) { throw 'vswhere.exe was not found; install or configure Visual Studio Build Tools v143 before building.' }
    $installationPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if ([string]::IsNullOrWhiteSpace($installationPath)) { throw 'No Visual Studio C++ Build Tools installation with the x86/x64 workload was found.' }
    $msbuild = Join-Path $installationPath 'MSBuild\Current\Bin\MSBuild.exe'
    if (-not (Test-Path -LiteralPath $msbuild)) { throw 'The selected Visual Studio installation has no MSBuild.exe.' }
    $v143 = Join-Path $installationPath 'VC\Tools\MSVC'
    if (-not (Test-Path -LiteralPath $v143)) { throw 'The selected Visual Studio installation has no v143 C++ toolset directory.' }
    return [pscustomobject]@{ InstallationPath = $installationPath; MsBuildPath = $msbuild; V143Path = $v143 }
}

function Get-RequiredRuntimeFiles {
    return @('yt-dlp.exe', 'ffmpeg.exe', 'ffprobe.exe', 'deno.exe', '7z.dll')
}

function Initialize-OfficialDependencies {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot, [string] $DependencyArchiveDirectory)
    $solutionParent = $SourceRoot
    foreach ($name in @('bit7z', 'nana', 'libpng', 'libjpeg-turbo-3.1.2')) {
        $target = Join-Path $solutionParent $name
        if (Test-Path -LiteralPath $target -PathType Container) { continue }
        if ([string]::IsNullOrWhiteSpace($DependencyArchiveDirectory)) { throw "Official dependency $name is absent; provide its reviewed archive directory." }
        $archive = Join-Path $DependencyArchiveDirectory ($name + '.zip')
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Reviewed dependency archive is missing: $archive" }
        Expand-Archive -LiteralPath $archive -DestinationPath $solutionParent -Force
        if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Archive $archive did not produce $target." }
    }
}

function Copy-CandidateFile {
    param([string] $Source, [string] $DestinationDirectory)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Required candidate input is missing: $Source" }
    Copy-Item -LiteralPath $Source -Destination (Join-Path $DestinationDirectory (Split-Path -Leaf $Source)) -Force
}

function Get-CandidateManifest {
    param([Parameter(Mandatory = $true)] [string] $CandidateRoot)
    $files = Get-ChildItem -LiteralPath $CandidateRoot -File -Recurse | Sort-Object FullName
    $versions = [ordered]@{
        product = (Get-Item -LiteralPath (Join-Path $CandidateRoot 'ytdlp-interface.exe')).VersionInfo.ProductVersion
        ytdlp = ((& (Join-Path $CandidateRoot 'yt-dlp.exe') '--version' 2>&1 | Select-Object -First 1) -as [string]).Trim()
        ffmpeg = ((& (Join-Path $CandidateRoot 'ffmpeg.exe') '-version' 2>&1 | Select-Object -First 1) -as [string]).Trim()
        ffprobe = ((& (Join-Path $CandidateRoot 'ffprobe.exe') '-version' 2>&1 | Select-Object -First 1) -as [string]).Trim()
        deno = ((& (Join-Path $CandidateRoot 'deno.exe') '--version' 2>&1 | Select-Object -First 1) -as [string]).Trim()
    }
    foreach ($name in $versions.Keys) { if ([string]::IsNullOrWhiteSpace($versions[$name])) { throw "Candidate $name version verification produced no output." } }
    return [ordered]@{
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        versions = $versions
        files = @($files | ForEach-Object {
            [ordered]@{ path = $_.FullName.Substring($CandidateRoot.Length).TrimStart('\', '/'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash; length = $_.Length }
        })
    }
}

function Test-CandidateAssembly {
    param([Parameter(Mandatory = $true)] [string] $CandidateRoot)
    $required = @('ytdlp-interface.exe') + (Get-RequiredRuntimeFiles) + @('locales\ko-KR.json', 'ytdlp-interface.json')
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $CandidateRoot $relative) -PathType Leaf)) { throw "Candidate assembly is missing $relative." }
    }
    $version = (Get-Item -LiteralPath (Join-Path $CandidateRoot 'ytdlp-interface.exe')).VersionInfo.ProductVersion
    if ($version -ne '2.19.1.0') { throw "Candidate product version must be 2.19.1.0, got $version." }
}

function Invoke-BuildCandidate {
    param([string] $SourceRoot, [string] $ParentRuntime, [string] $CandidateBase, [string] $DependencyArchiveDirectory)
    $source = [IO.Path]::GetFullPath($SourceRoot)
    if ([string]::IsNullOrWhiteSpace($ParentRuntime)) { $ParentRuntime = Split-Path -Parent $source }
    if ([string]::IsNullOrWhiteSpace($CandidateBase)) { $CandidateBase = Join-Path $source 'candidate-runtime' }
    $solution = Join-Path $source 'ytdlp-interface\ytdlp-interface.sln'
    $project = Join-Path $source 'ytdlp-interface\ytdlp-interface.vcxproj'
    $catalog = Join-Path $source 'locales\ko-KR.json'
    $settings = Join-Path $ParentRuntime 'ytdlp-interface.json'
    foreach ($path in @($solution, $project, $catalog, $settings)) { if (-not (Test-Path -LiteralPath $path)) { throw "Required build input is missing: $path" } }
    if (-not (Select-String -LiteralPath $project -Pattern '<PlatformToolset>v143</PlatformToolset>' -Quiet)) { throw 'The project does not declare v143.' }
    Initialize-OfficialDependencies -SourceRoot $source -DependencyArchiveDirectory $DependencyArchiveDirectory
    $tools = Get-VsBuildTools
    & $tools.MsBuildPath $solution '/m' '/t:Build' '/p:Configuration=Release' '/p:Platform=x64'
    if ($LASTEXITCODE -ne 0) { throw "Release x64 build failed with exit code $LASTEXITCODE." }
    $product = Join-Path $source 'ytdlp-interface\x64\Release\ytdlp-interface.exe'
    if (-not (Test-Path -LiteralPath $product -PathType Leaf)) { throw "Release x64 product is missing: $product" }
    $candidate = New-CandidateRoot -BaseDirectory $CandidateBase
    try {
        Copy-CandidateFile -Source $product -DestinationDirectory $candidate
        foreach ($name in Get-RequiredRuntimeFiles) { Copy-CandidateFile -Source (Join-Path $ParentRuntime $name) -DestinationDirectory $candidate }
        Copy-CandidateFile -Source $settings -DestinationDirectory $candidate
        Import-Module -Name (Join-Path $source 'tools\runtime-maintenance.psm1') -Force
        RepairSettings -SettingsPath (Join-Path $candidate 'ytdlp-interface.json') -Confirm:$false | Out-Null
        $localeDirectory = Join-Path $candidate 'locales'; [IO.Directory]::CreateDirectory($localeDirectory) | Out-Null
        Copy-CandidateFile -Source $catalog -DestinationDirectory $localeDirectory
        Test-CandidateAssembly -CandidateRoot $candidate
        $manifest = Get-CandidateManifest -CandidateRoot $candidate
        [IO.File]::WriteAllText((Join-Path $candidate 'candidate-manifest.json'), ($manifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{ CandidateRoot = $candidate; ManifestPath = (Join-Path $candidate 'candidate-manifest.json') }
    }
    catch { if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue }; throw }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Run) { Write-Output 'No action taken. Re-run with -Run to build and assemble a candidate.' }
    else { Invoke-BuildCandidate -SourceRoot $SourceRoot -ParentRuntime $ParentRuntime -CandidateBase $CandidateBase -DependencyArchiveDirectory $DependencyArchiveDirectory }
}
