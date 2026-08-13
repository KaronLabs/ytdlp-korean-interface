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
Import-Module -Name (Join-Path $PSScriptRoot 'candidate-manifest.psm1') -Force

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

function ConvertTo-ProcessArgumentLine {
    param([string[]] $Arguments)
    return (($Arguments | ForEach-Object { Quote-WindowsArgument ([string]$_) }) -join ' ')
}

function Quote-WindowsArgument {
    param([Parameter(Mandatory = $true)] [string] $Argument)
    if ($Argument.Length -ne 0 -and $Argument -notmatch '[\s"]') { return $Argument }
    $quoted = '"'; $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') { $backslashes++; continue }
        if ($character -eq '"') { $quoted += [string]::new([char]92, ($backslashes * 2 + 1)) + '"'; $backslashes = 0; continue }
        if ($backslashes -gt 0) { $quoted += [string]::new([char]92, $backslashes); $backslashes = 0 }
        $quoted += $character
    }
    if ($backslashes -gt 0) { $quoted += [string]::new([char]92, ($backslashes * 2)) }
    return $quoted + '"'
}

function Normalize-ProcessEnvironmentPath {
    param([Parameter(Mandatory = $true)] [object] $Environment)
    $keys = @($Environment.Keys | ForEach-Object { [string]$_ } | Where-Object { $_ -ieq 'Path' })
    if ($keys.Count -le 1) { return }
    $value = if ($keys -ccontains 'Path') { [string]$Environment['Path'] } else { [string]$Environment[$keys[0]] }
    foreach ($key in $keys) { $Environment.Remove($key) | Out-Null }
    $Environment['Path'] = $value
}

function Get-CanonicalProcessEnvironment {
    $environment = New-Object Collections.Specialized.StringDictionary
    $lines = & $env:ComSpec /d /c set
    if ($LASTEXITCODE -ne 0) { throw 'cmd.exe could not read the Windows process environment.' }
    foreach ($line in @($lines)) {
        $separator = $line.IndexOf('=')
        if ($separator -le 0) { continue }
        $environment[$line.Substring(0, $separator)] = $line.Substring($separator + 1)
    }
    Normalize-ProcessEnvironmentPath -Environment $environment
    return ,$environment
}

function Invoke-CheckedProcess {
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [string[]] $Arguments = @(),
        [Parameter(Mandatory = $true)] [string] $Name,
        [switch] $NormalizeEnvironment,
        [string] $WorkingDirectory,
        [Collections.IDictionary] $EnvironmentOverrides
    )
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ConvertTo-ProcessArgumentLine -Arguments $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { $startInfo.WorkingDirectory = $WorkingDirectory }
    if ($NormalizeEnvironment) {
        $null = $startInfo.EnvironmentVariables
        $processEnvironment = $startInfo.EnvironmentVariables
        $processEnvironment.Clear()
        $canonicalEnvironment = Get-CanonicalProcessEnvironment
        foreach ($key in $canonicalEnvironment.Keys) { $processEnvironment[$key] = $canonicalEnvironment[$key] }
    }
    if ($null -ne $EnvironmentOverrides) {
        $null = $startInfo.EnvironmentVariables
        foreach ($key in $EnvironmentOverrides.Keys) { $startInfo.EnvironmentVariables[[string]$key] = [string]$EnvironmentOverrides[$key] }
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "$Name could not be started." }
    try {
        $process.Handle | Out-Null
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $process.Refresh()
        $stdout = $stdoutTask.Result.Trim()
        $stderr = $stderrTask.Result.Trim()
        if ($process.ExitCode -ne 0) { throw "$Name exited with code $($process.ExitCode). stdout=$stdout stderr=$stderr" }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; StandardOutput = $stdout; StandardError = $stderr }
    }
    finally { $process.Dispose() }
}

function Get-VsBuildTools {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }
    $vswhere = $candidates | Select-Object -First 1
    if ($null -eq $vswhere) { throw 'vswhere.exe was not found; install or configure Visual Studio Build Tools v143 before building.' }
    $installationPath = (Invoke-CheckedProcess -FilePath $vswhere -Arguments @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath') -Name 'vswhere C++ Build Tools lookup').StandardOutput.Trim()
    if ([string]::IsNullOrWhiteSpace($installationPath)) { throw 'No Visual Studio C++ Build Tools installation with the x86/x64 workload was found.' }
    $msbuild = Join-Path $installationPath 'MSBuild\Current\Bin\MSBuild.exe'
    if (-not (Test-Path -LiteralPath $msbuild)) { throw 'The selected Visual Studio installation has no MSBuild.exe.' }
    $v143 = Join-Path $installationPath 'VC\Tools\MSVC'
    if (-not (Test-Path -LiteralPath $v143)) { throw 'The selected Visual Studio installation has no v143 C++ toolset directory.' }
    $versionFile = Join-Path $installationPath 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
    if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) { throw 'The selected Visual Studio installation has no default C++ toolset identity.' }
    $vcToolsVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
    $compiler = Join-Path $v143 ($vcToolsVersion + '\bin\Hostx64\x64\cl.exe')
    $linker = Join-Path $v143 ($vcToolsVersion + '\bin\Hostx64\x64\link.exe')
    foreach ($path in @($compiler, $linker)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'The selected Visual Studio installation has an incomplete x64 C++ toolset.' } }
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
    $sdkVersions = @(Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'bin') -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^10\.\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending)
    $sdk = $sdkVersions | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64\rc.exe') -PathType Leaf } | Select-Object -First 1
    if ($null -eq $sdk) { throw 'A Windows 10/11 SDK x64 resource compiler is required.' }
    $sdkVersion = $sdk.Name
    $resourceCompiler = Join-Path $sdk.FullName 'x64\rc.exe'
    $sdkIdentity = Join-Path $sdkRoot ('Lib\' + $sdkVersion + '\um\x64\kernel32.lib')
    if (-not (Test-Path -LiteralPath $sdkIdentity -PathType Leaf)) { throw 'The selected Windows SDK has no x64 kernel32 import library.' }
    return [pscustomobject]@{
        InstallationPath = $installationPath; MsBuildPath = $msbuild; V143Path = $v143
        VCToolsVersion = $vcToolsVersion; CompilerPath = $compiler; LinkerPath = $linker
        WindowsSdkVersion = $sdkVersion; ResourceCompilerPath = $resourceCompiler; WindowsSdkIdentityPath = $sdkIdentity
    }
}

function Get-CmakeExecutable {
    param([Parameter(Mandatory = $true)] [string] $VisualStudioInstallation)
    $fromPath = Get-Command -Name 'cmake.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $fromPath) { return $fromPath.Path }
    $fromVisualStudio = Join-Path $VisualStudioInstallation 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (Test-Path -LiteralPath $fromVisualStudio -PathType Leaf) { return $fromVisualStudio }
    throw 'cmake.exe was not found; install or configure CMake before building libjpeg-turbo.'
}

function Get-RequiredRuntimeFiles {
    return @('yt-dlp.exe', 'ffmpeg.exe', 'ffprobe.exe', 'deno.exe', '7z.dll')
}

function Test-PathOverlap {
    param([Parameter(Mandatory = $true)] [string] $First, [Parameter(Mandatory = $true)] [string] $Second)
    return (Test-PathContained -Root $First -Path $Second) -or (Test-PathContained -Root $Second -Path $First) -or
        ([IO.Path]::GetFullPath($First).TrimEnd('\', '/') -eq [IO.Path]::GetFullPath($Second).TrimEnd('\', '/'))
}

function Get-TrustedSevenZip {
    $paths = @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'), (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) }
    $sevenZip = $paths | Select-Object -First 1
    if ($null -eq $sevenZip) { throw '7z.exe from the trusted Program Files 7-Zip installation is required to inspect dependencies.7z before extraction.' }
    return $sevenZip
}

function Get-DependencyArchiveManifest {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot)
    $path = Join-Path $SourceRoot 'tools\dependency-archives.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Dependency archive manifest is missing.' }
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or @($manifest.archives).Count -ne 1) { throw 'Dependency archive manifest is invalid.' }
    return $manifest.archives[0]
}

function Get-GitTrackedPaths {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot, [Parameter(Mandatory = $true)] [string] $GitPath)
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $safeDirectory = 'safe.directory=' + $source
    $paths = @(& $GitPath -c $safeDirectory -C $source ls-files --cached 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or $paths.Count -eq 0) { throw 'Git could not enumerate tracked candidate source inputs.' }
    return @($paths)
}

function Get-SourceInputAttestation {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $Commit,
        [AllowEmptyString()] [string] $StatusPorcelain,
        [Parameter(Mandatory = $true)] [string[]] $TrackedPaths
    )
    if (-not [string]::IsNullOrWhiteSpace($StatusPorcelain)) { throw 'source_worktree_dirty' }
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $records = @()
    foreach ($relative in @($TrackedPaths | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw 'source_input_invalid' }
        $path = Join-Path $source $relative
        if (-not (Test-PathContained -Root $source -Path $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'source_input_invalid' }
        $item = Get-Item -LiteralPath $path
        $records += (($relative.Replace('\', '/')) + "`0" + $item.Length + "`0" + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant())
    }
    if ($records.Count -eq 0) { throw 'source_input_invalid' }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($records -join "`n"))
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $digest = ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '') }
    finally { $hasher.Dispose() }
    return [ordered]@{ commit = $Commit; dirty = $false; treeSha256 = $digest; trackedFileCount = $records.Count }
}

function Get-SourceAttestation {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot, [string] $GitPath, [string[]] $TrackedPaths)
    $source = [IO.Path]::GetFullPath($SourceRoot)
    if ([string]::IsNullOrWhiteSpace($GitPath)) {
        $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $git) { throw 'Git is required to attest the candidate source revision.' }
        $GitPath = $git.Source
    }
    if (-not (Test-Path -LiteralPath $GitPath -PathType Leaf)) { throw 'Git executable is missing for source attestation.' }
    $safeDirectory = 'safe.directory=' + $source
    $commit = (& $GitPath -c $safeDirectory -C $source rev-parse --verify HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Git could not verify the candidate source revision.' }
    $status = & $GitPath -c $safeDirectory -C $source status --porcelain=v1 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Git could not inspect the candidate source status.' }
    if ([string]::IsNullOrWhiteSpace($commit)) { throw 'Git source revision is empty.' }
    if ($null -eq $TrackedPaths -or $TrackedPaths.Count -eq 0) { $TrackedPaths = Get-GitTrackedPaths -SourceRoot $source -GitPath $GitPath }
    return Get-SourceInputAttestation -SourceRoot $source -Commit $commit -StatusPorcelain $status -TrackedPaths $TrackedPaths
}

function Test-ArchiveEntrySafe {
    param([string] $Entry, [string[]] $ExpectedRoots)
    if ([string]::IsNullOrWhiteSpace($Entry) -or $Entry -match '^[A-Za-z]:|^[/\\]|(^|[/\\])\.\.([/\\]|$)') { return $false }
    $root = ($Entry -split '[/\\]')[0]
    return $ExpectedRoots -contains $root
}

function Get-ArchiveEntriesFromListing {
    param([string[]] $Listing)
    $paths = @($Listing | Where-Object { $_ -match '^Path = ' } | ForEach-Object { $_.Substring(7) })
    if ($paths.Count -lt 2) { throw 'Dependency archive listing has no entries beyond its archive header.' }
    return @($paths | Select-Object -Skip 1)
}

function Initialize-OfficialDependencies {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot, [string] $DependencyArchiveDirectory)
    $manifest = Get-DependencyArchiveManifest -SourceRoot $SourceRoot
    $roots = @($manifest.roots)
    $missing = @($roots | Where-Object { -not (Test-Path -LiteralPath (Join-Path $SourceRoot $_) -PathType Container) })
    if ([string]::IsNullOrWhiteSpace($DependencyArchiveDirectory)) { throw 'Reviewed dependency archive directory is required for candidate builds.' }
    $archive = Join-Path $DependencyArchiveDirectory $manifest.name
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Reviewed dependency archive is missing: $archive" }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant() -cne ([string]$manifest.sha256).ToUpperInvariant()) { throw 'Dependency archive SHA-256 does not match the source-controlled manifest.' }
    $sevenZip = Get-TrustedSevenZip
    $listing = (Invoke-CheckedProcess -FilePath $sevenZip -Arguments @('l', '-slt', $archive) -Name '7z dependency inspection').StandardOutput -split "`r?`n"
    $entries = Get-ArchiveEntriesFromListing -Listing $listing
    if ($entries.Count -eq 0) { throw 'Dependency archive contains no inspectable entries.' }
    foreach ($entry in $entries) { if (-not (Test-ArchiveEntrySafe -Entry $entry -ExpectedRoots $roots)) { throw 'Dependency archive contains an unsafe or unexpected entry.' } }
    if ($missing.Count -eq 0) { return }
    $staging = Join-Path (Join-Path $SourceRoot 'dependencies') ('staging-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($staging) | Out-Null
    try {
        Invoke-CheckedProcess -FilePath $sevenZip -Arguments @('x', $archive, ("-o" + $staging), '-y') -Name '7z dependency extraction' | Out-Null
        foreach ($name in $missing) {
            $source = Join-Path $staging $name; $target = Join-Path $SourceRoot $name
            if (-not (Test-Path -LiteralPath $source -PathType Container) -or (Test-Path -LiteralPath $target)) { throw 'Dependency staging validation failed.' }
            Move-Item -LiteralPath $source -Destination $target
        }
    }
    finally { if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue } }
}

function New-IsolatedBuildSource {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $WorkspaceRoot,
        [Parameter(Mandatory = $true)] [string[]] $DependencyRoots,
        [string[]] $TrackedPaths
    )
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $isolated = Join-Path $WorkspaceRoot 'source'
    [IO.Directory]::CreateDirectory($isolated) | Out-Null
    if ($null -eq $TrackedPaths -or $TrackedPaths.Count -eq 0) {
        $git = Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $TrackedPaths = Get-GitTrackedPaths -SourceRoot $source -GitPath $git.Source
    }
    foreach ($relative in @($TrackedPaths | Sort-Object -Unique)) {
        $rootName = ($relative -split '[/\\]')[0]
        if ($DependencyRoots -contains $rootName -or $rootName -eq '.git') { continue }
        $from = Join-Path $source $relative; $to = Join-Path $isolated $relative
        if (-not (Test-PathContained -Root $source -Path $from) -or -not (Test-Path -LiteralPath $from -PathType Leaf)) { throw 'source_input_invalid' }
        [IO.Directory]::CreateDirectory((Split-Path -Parent $to)) | Out-Null
        Copy-Item -LiteralPath $from -Destination $to -Force
    }
    return $isolated
}

function New-IsolatedBuildWorkspace {
    param([Parameter(Mandatory = $true)] [string] $WorkspaceBase)
    $base = [IO.Path]::GetFullPath($WorkspaceBase)
    [IO.Directory]::CreateDirectory($base) | Out-Null
    do { $workspace = Join-Path $base ('b-' + [Guid]::NewGuid().ToString('N')) } while (Test-Path -LiteralPath $workspace)
    if (-not (Test-PathContained -Root $base -Path $workspace)) { throw 'Isolated build workspace escaped its configured base directory.' }
    [IO.Directory]::CreateDirectory($workspace) | Out-Null
    return $workspace
}

function New-HermeticBuildContext {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $WorkspaceRoot,
        [string] $VCToolsVersion,
        [string] $WindowsSdkVersion
    )
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $userRoot = Join-Path ([IO.Path]::GetFullPath($WorkspaceRoot)) 'empty-user-root'
    [IO.Directory]::CreateDirectory($userRoot) | Out-Null
    $properties = [ordered]@{
        Configuration = 'Release'
        Platform = 'x64'
        PlatformToolset = 'v143'
        ImportDirectoryBuildProps = 'false'
        ImportDirectoryBuildTargets = 'false'
        UserRootDir = '<hermetic-user-root>'
    }
    $arguments = @(
        '/p:Configuration=Release', '/p:Platform=x64', '/p:PlatformToolset=v143',
        '/p:ImportDirectoryBuildProps=false', '/p:ImportDirectoryBuildTargets=false', ('/p:UserRootDir=' + $userRoot + '\')
    )
    if (-not [string]::IsNullOrWhiteSpace($VCToolsVersion)) { $properties.VCToolsVersion = $VCToolsVersion; $arguments += '/p:VCToolsVersion=' + $VCToolsVersion }
    if (-not [string]::IsNullOrWhiteSpace($WindowsSdkVersion)) { $properties.WindowsTargetPlatformVersion = $WindowsSdkVersion; $arguments += '/p:WindowsTargetPlatformVersion=' + $WindowsSdkVersion }
    $vsGlobals = @(
        'ImportDirectoryBuildProps=false', 'ImportDirectoryBuildTargets=false', ('UserRootDir=' + $userRoot + '\')
    )
    if (-not [string]::IsNullOrWhiteSpace($VCToolsVersion)) { $vsGlobals += 'VCToolsVersion=' + $VCToolsVersion }
    if (-not [string]::IsNullOrWhiteSpace($WindowsSdkVersion)) { $vsGlobals += 'WindowsTargetPlatformVersion=' + $WindowsSdkVersion }
    return [pscustomobject]@{
        UserRootDirectory = $userRoot
        MsBuildArguments = $arguments
        CmakeVsGlobalsArgument = '-DCMAKE_VS_GLOBALS=' + ($vsGlobals -join ';')
        EffectiveProperties = $properties
        WorkingDirectory = $source
        AttestedWorkingDirectory = '<source>'
        EnvironmentOverrides = [ordered]@{ PreferredToolArchitecture = 'x64' }
        AttestedEnvironment = [ordered]@{ PreferredToolArchitecture = 'x64' }
    }
}

function Get-ReleaseX64DependencyPlan {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [string] $MsBuildPath = 'MSBuild.exe',
        [string] $CmakePath = 'cmake.exe',
        [string[]] $CommonMsBuildArguments = @('/p:Configuration=Release', '/p:Platform=x64', '/p:PlatformToolset=v143'),
        [string] $CmakeVsGlobalsArgument
    )
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $release = @('/m', '/t:Build') + @($CommonMsBuildArguments)
    $libPngOutput = Join-Path $source 'libpng\x64\Release'
    $jpegOutput = Join-Path $source 'libjpeg-turbo-3.1.2\out\build\x64-Release'
    return @(
        [pscustomobject]@{
            Name = 'bit7z'; SourceDirectory = (Join-Path $source 'bit7z'); FilePath = $MsBuildPath
            Arguments = @((Join-Path $source 'bit7z\bit7z.sln')) + $release
            LibraryPath = (Join-Path $source 'bit7z\bin\x64\bit7z64.lib'); BuildArguments = @()
        },
        [pscustomobject]@{
            Name = 'Nana'; SourceDirectory = (Join-Path $source 'nana'); FilePath = $MsBuildPath
            Arguments = @((Join-Path $source 'nana\build\vc2022\nana.sln')) + $release
            LibraryPath = (Join-Path $source 'nana\build\bin\nana_v143_Release_x64.lib'); BuildArguments = @()
        },
        [pscustomobject]@{
            Name = 'libpng'; SourceDirectory = (Join-Path $source 'libpng'); FilePath = $MsBuildPath
            Arguments = @((Join-Path $source 'libpng\libpng.sln')) + $release + ('/p:OutDir=' + $libPngOutput + '\')
            LibraryPath = (Join-Path $libPngOutput 'libpng.lib'); BuildArguments = @()
        },
        [pscustomobject]@{
            Name = 'libjpeg-turbo'; SourceDirectory = (Join-Path $source 'libjpeg-turbo-3.1.2'); FilePath = $CmakePath
            Arguments = @('-S', (Join-Path $source 'libjpeg-turbo-3.1.2'), '-B', $jpegOutput, '-G', 'Visual Studio 17 2022', '-A', 'x64', '-T', 'v143') + @($(if (-not [string]::IsNullOrWhiteSpace($CmakeVsGlobalsArgument)) { $CmakeVsGlobalsArgument })) + @('-DENABLE_SHARED=OFF', '-DENABLE_STATIC=ON', '-DWITH_TURBOJPEG=ON', '-DWITH_CRT_DLL=OFF', ('-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE=' + $jpegOutput))
            LibraryPath = (Join-Path $jpegOutput 'turbojpeg-static.lib')
            BuildArguments = @('--build', $jpegOutput, '--config', 'Release', '--target', 'turbojpeg-static', '--') + @($CommonMsBuildArguments)
        }
    )
}

function Test-ReleaseX64DependencyLibraries {
    param([Parameter(Mandatory = $true)] [object[]] $Plan)
    return (@($Plan | Where-Object { -not (Test-Path -LiteralPath $_.LibraryPath -PathType Leaf) }).Count -eq 0)
}

function Get-DependencyLibraryAttestation {
    param([Parameter(Mandatory = $true)] [object[]] $Plan)
    return @($Plan | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_.LibraryPath -PathType Leaf)) { throw "Dependency linker input is missing: $($_.Name)" }
        $file = Get-Item -LiteralPath $_.LibraryPath
        [ordered]@{ name = $_.Name; library = $file.Name; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant(); length = $file.Length }
    })
}

function Assert-DependencyLibraryAttestationUnchanged {
    param([Parameter(Mandatory = $true)] [object[]] $Plan, [Parameter(Mandatory = $true)] [object[]] $Before)
    $after = @(Get-DependencyLibraryAttestation -Plan $Plan)
    if ($after.Count -ne $Before.Count) { throw 'dependency_linker_input_changed' }
    for ($index = 0; $index -lt $after.Count; $index++) {
        if ($after[$index].name -ne $Before[$index].name -or $after[$index].library -ne $Before[$index].library -or
            $after[$index].sha256 -cne $Before[$index].sha256 -or $after[$index].length -ne $Before[$index].length) { throw 'dependency_linker_input_changed' }
    }
}

function Get-BuildToolchainAttestation {
    param(
        [Parameter(Mandatory = $true)] [object] $Tools,
        [Parameter(Mandatory = $true)] [string] $CmakePath,
        [scriptblock] $IdentityReader
    )
    $entries = @(
        [pscustomobject]@{ name = 'msbuild'; path = $Tools.MsBuildPath; arguments = @('/version') },
        [pscustomobject]@{ name = 'cmake'; path = $CmakePath; arguments = @('--version') },
        [pscustomobject]@{ name = 'cl'; path = $Tools.CompilerPath; version = $Tools.VCToolsVersion },
        [pscustomobject]@{ name = 'link'; path = $Tools.LinkerPath; version = $Tools.VCToolsVersion },
        [pscustomobject]@{ name = 'rc'; path = $Tools.ResourceCompilerPath; version = $Tools.WindowsSdkVersion },
        [pscustomobject]@{ name = 'windows-sdk'; path = $Tools.WindowsSdkIdentityPath; version = $Tools.WindowsSdkVersion }
    )
    return @($entries | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_.path -PathType Leaf)) { throw "Build toolchain input is missing: $($_.name)" }
        $version = if ($null -ne $IdentityReader) { [string](& $IdentityReader $_.name $_.path) }
            elseif ($null -ne $_.PSObject.Properties['arguments']) { Invoke-CheckedExecutable -Path $_.path -Arguments $_.arguments -Name $_.name }
            else { [string]$_.version }
        [ordered]@{
            name = $_.name
            path = $_.path
            sha256 = (Get-FileHash -LiteralPath $_.path -Algorithm SHA256).Hash.ToUpperInvariant()
            version = $version.Trim()
        }
    })
}

function Get-NormalizedBuildArgument {
    param([Parameter(Mandatory = $true)] [string] $Argument, [Parameter(Mandatory = $true)] [string] $SourceRoot, [string] $HermeticUserRoot)
    $normalized = $Argument.Replace([IO.Path]::GetFullPath($SourceRoot), '<source>')
    if (-not [string]::IsNullOrWhiteSpace($HermeticUserRoot)) { $normalized = $normalized.Replace([IO.Path]::GetFullPath($HermeticUserRoot), '<hermetic-user-root>') }
    return $normalized
}

function Get-BuildCommandAttestation {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [object[]] $DependencyPlan,
        [Parameter(Mandatory = $true)] [string] $ProductExecutable,
        [Parameter(Mandatory = $true)] [string[]] $ProductArguments,
        [object] $BuildContext
    )
    $userRoot = if ($null -eq $BuildContext) { $null } else { $BuildContext.UserRootDirectory }
    $workingDirectory = if ($null -eq $BuildContext) { '<source>' } else { $BuildContext.AttestedWorkingDirectory }
    $properties = if ($null -eq $BuildContext) { [ordered]@{} } else { $BuildContext.EffectiveProperties }
    $environment = if ($null -eq $BuildContext) { [ordered]@{} } else { $BuildContext.AttestedEnvironment }
    $commands = @()
    foreach ($dependency in $DependencyPlan) {
        $phase = if ($dependency.Name -eq 'libjpeg-turbo') { 'configure' } else { 'build' }
        $commands += [ordered]@{ name = "$($dependency.Name) Release x64 $phase"; executable = (Split-Path -Leaf $dependency.FilePath); arguments = @($dependency.Arguments | ForEach-Object { Get-NormalizedBuildArgument -Argument ([string]$_) -SourceRoot $SourceRoot -HermeticUserRoot $userRoot }); workingDirectory = $workingDirectory; effectiveProperties = $properties; environment = $environment }
        if ($dependency.BuildArguments.Count -ne 0) {
            $commands += [ordered]@{ name = "$($dependency.Name) Release x64 build"; executable = (Split-Path -Leaf $dependency.FilePath); arguments = @($dependency.BuildArguments | ForEach-Object { Get-NormalizedBuildArgument -Argument ([string]$_) -SourceRoot $SourceRoot -HermeticUserRoot $userRoot }); workingDirectory = $workingDirectory; effectiveProperties = $properties; environment = $environment }
        }
    }
    $commands += [ordered]@{ name = 'Release x64 MSBuild'; executable = (Split-Path -Leaf $ProductExecutable); arguments = @($ProductArguments | ForEach-Object { Get-NormalizedBuildArgument -Argument ([string]$_) -SourceRoot $SourceRoot -HermeticUserRoot $userRoot }); workingDirectory = $workingDirectory; effectiveProperties = $properties; environment = $environment }
    return @($commands)
}

function Invoke-ReleaseX64Dependencies {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $MsBuildPath,
        [Parameter(Mandatory = $true)] [string] $CmakePath,
        [object] $BuildContext
    )
    $commonArguments = if ($null -eq $BuildContext) { @('/p:Configuration=Release', '/p:Platform=x64', '/p:PlatformToolset=v143') } else { @($BuildContext.MsBuildArguments) }
    $plan = Get-ReleaseX64DependencyPlan -SourceRoot $SourceRoot -MsBuildPath $MsBuildPath -CmakePath $CmakePath -CommonMsBuildArguments $commonArguments -CmakeVsGlobalsArgument $(if ($null -eq $BuildContext) { $null } else { $BuildContext.CmakeVsGlobalsArgument })
    foreach ($dependency in $plan) {
        if (-not (Test-Path -LiteralPath $dependency.SourceDirectory -PathType Container)) { throw "Dependency source is missing: $($dependency.Name)" }
        Invoke-CheckedProcess -FilePath $dependency.FilePath -Arguments $dependency.Arguments -Name "$($dependency.Name) Release x64 build" -NormalizeEnvironment -WorkingDirectory $(if ($null -eq $BuildContext) { $SourceRoot } else { $BuildContext.WorkingDirectory }) -EnvironmentOverrides $(if ($null -eq $BuildContext) { $null } else { $BuildContext.EnvironmentOverrides }) | Out-Null
        if ($dependency.BuildArguments.Count -ne 0) {
            Invoke-CheckedProcess -FilePath $dependency.FilePath -Arguments $dependency.BuildArguments -Name "$($dependency.Name) Release x64 build" -NormalizeEnvironment -WorkingDirectory $(if ($null -eq $BuildContext) { $SourceRoot } else { $BuildContext.WorkingDirectory }) -EnvironmentOverrides $(if ($null -eq $BuildContext) { $null } else { $BuildContext.EnvironmentOverrides }) | Out-Null
        }
    }
    $missing = @($plan | Where-Object { -not (Test-Path -LiteralPath $_.LibraryPath -PathType Leaf) })
    if ($missing.Count -ne 0) { throw ('Release x64 dependency libraries are missing: ' + (($missing | ForEach-Object { Split-Path -Leaf $_.LibraryPath }) -join ', ')) }
    return $plan
}

function Copy-CandidateFile {
    param([string] $Source, [string] $DestinationDirectory)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Required candidate input is missing: $Source" }
    Copy-Item -LiteralPath $Source -Destination (Join-Path $DestinationDirectory (Split-Path -Leaf $Source)) -Force
}

function Invoke-CheckedExecutable {
    param([Parameter(Mandatory = $true)] [string] $Path, [Parameter(Mandatory = $true)] [string[]] $Arguments, [string] $Name)
    $result = Invoke-CheckedProcess -FilePath $Path -Arguments $Arguments -Name "Candidate $Name version check"
    if ([string]::IsNullOrWhiteSpace($result.StandardOutput)) { throw "Candidate $Name version check produced no output." }
    return $result.StandardOutput
}

function Assert-ParentProvenanceShape {
    param([Parameter(Mandatory = $true)] [object] $Provenance)
    if ($Provenance.repository -ne 'yt-dlp/yt-dlp-nightly-builds' -or $Provenance.channel -ne 'nightly' -or [string]::IsNullOrWhiteSpace([string]$Provenance.tag)) { throw 'Parent runtime provenance is not the official nightly channel.' }
    $previousVersion = $Provenance.PSObject.Properties['previousVersion']
    $previousSha256 = $Provenance.PSObject.Properties['previousSha256']
    $backupPath = $Provenance.PSObject.Properties['backupPath']
    if ($null -eq $previousVersion -or $null -eq $previousSha256 -or $null -eq $backupPath -or [string]::IsNullOrWhiteSpace([string]$previousVersion.Value) -or ([string]$previousSha256.Value).ToUpperInvariant() -notmatch '^[A-F0-9]{64}$' -or [string]::IsNullOrWhiteSpace([string]$backupPath.Value)) { throw 'Parent runtime provenance rollback identity is missing.' }
}

function Get-BackupYtDlpVersion {
    param([Parameter(Mandatory = $true)] [string] $BackupPath, [scriptblock] $VersionReader)
    $temporaryExecutable = Join-Path ([IO.Path]::GetTempPath()) ('ytdlp-backup-version-' + [Guid]::NewGuid().ToString('N') + '.exe')
    try {
        Copy-Item -LiteralPath $BackupPath -Destination $temporaryExecutable
        if ($null -ne $VersionReader) { return [string](& $VersionReader $temporaryExecutable) }
        return (Invoke-CheckedExecutable -Path $temporaryExecutable -Arguments @('--version') -Name 'yt-dlp backup').Trim()
    }
    finally { if (Test-Path -LiteralPath $temporaryExecutable) { Remove-Item -LiteralPath $temporaryExecutable -Force -ErrorAction SilentlyContinue } }
}

function Get-VerifiedParentRuntime {
    param([Parameter(Mandatory = $true)] [string] $ParentRuntime)
    $parent = [IO.Path]::GetFullPath($ParentRuntime)
    $provenancePath = Join-Path $parent 'yt-dlp-provenance.json'
    if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) { throw 'Parent runtime yt-dlp provenance is missing.' }
    $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
    Assert-ParentProvenanceShape -Provenance $provenance
    $ytDlp = Join-Path $parent 'yt-dlp.exe'
    if (-not (Test-Path -LiteralPath $ytDlp -PathType Leaf)) { throw 'Parent runtime yt-dlp.exe is missing.' }
    $hash = (Get-FileHash -LiteralPath $ytDlp -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($hash -cne ([string]$provenance.sha256).ToUpperInvariant()) { throw 'Parent runtime yt-dlp hash does not match provenance.' }
    $backupPath = [IO.Path]::GetFullPath([string]$provenance.backupPath)
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne ([string]$provenance.previousSha256).ToUpperInvariant()) { throw 'Parent runtime yt-dlp backup does not match provenance rollback identity.' }
    if ((Get-BackupYtDlpVersion -BackupPath $backupPath) -ne [string]$provenance.previousVersion) { throw 'Parent runtime yt-dlp backup version does not match provenance rollback identity.' }
    $version = Invoke-CheckedExecutable -Path $ytDlp -Arguments @('--version') -Name 'yt-dlp'
    if ($version.Trim() -ne ([string]$provenance.tag).Trim()) { throw 'Parent runtime yt-dlp version does not match provenance tag.' }
    foreach ($check in @(@('ffmpeg.exe', '-version', 'ffmpeg'), @('ffprobe.exe', '-version', 'ffprobe'), @('deno.exe', '--version', 'deno'))) {
        Invoke-CheckedExecutable -Path (Join-Path $parent $check[0]) -Arguments @($check[1]) -Name $check[2] | Out-Null
    }
    return [pscustomobject]@{ Path = $parent; YtDlpHash = $hash; YtDlpVersion = $version.Trim(); Provenance = $provenance }
}

function Get-CandidateManifest {
    param([Parameter(Mandatory = $true)] [string] $CandidateRoot, [object] $Attestation)
    $files = Get-ChildItem -LiteralPath $CandidateRoot -File -Recurse | Sort-Object FullName
    $versions = [ordered]@{
        product = (Get-Item -LiteralPath (Join-Path $CandidateRoot 'ytdlp-interface.exe')).VersionInfo.ProductVersion
        ytdlp = Invoke-CheckedExecutable -Path (Join-Path $CandidateRoot 'yt-dlp.exe') -Arguments @('--version') -Name 'yt-dlp'
        ffmpeg = Invoke-CheckedExecutable -Path (Join-Path $CandidateRoot 'ffmpeg.exe') -Arguments @('-version') -Name 'ffmpeg'
        ffprobe = Invoke-CheckedExecutable -Path (Join-Path $CandidateRoot 'ffprobe.exe') -Arguments @('-version') -Name 'ffprobe'
        deno = Invoke-CheckedExecutable -Path (Join-Path $CandidateRoot 'deno.exe') -Arguments @('--version') -Name 'deno'
    }
    foreach ($name in $versions.Keys) { if ([string]::IsNullOrWhiteSpace($versions[$name])) { throw "Candidate $name version verification produced no output." } }
    return [ordered]@{
        schemaVersion = 1
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        attestation = $Attestation
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
    $parent = [IO.Path]::GetFullPath($ParentRuntime)
    if ([string]::IsNullOrWhiteSpace($CandidateBase)) { $CandidateBase = Join-Path ([IO.Path]::GetTempPath()) 'ytdlp-interface-candidates' }
    $candidateBase = [IO.Path]::GetFullPath($CandidateBase)
    if (Test-PathOverlap -First $parent -Second $candidateBase) { throw 'Candidate base must not contain, or be contained by, the preserved parent runtime.' }
    $solution = Join-Path $source 'ytdlp-interface\ytdlp-interface.sln'
    $project = Join-Path $source 'ytdlp-interface\ytdlp-interface.vcxproj'
    $catalog = Join-Path $source 'locales\ko-KR.json'
    $settings = Join-Path $ParentRuntime 'ytdlp-interface.json'
    foreach ($path in @($solution, $project, $catalog, $settings)) { if (-not (Test-Path -LiteralPath $path)) { throw "Required build input is missing: $path" } }
    if (-not (Select-String -LiteralPath $project -Pattern '<PlatformToolset>v143</PlatformToolset>' -Quiet)) { throw 'The project does not declare v143.' }
    $git = Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $trackedPaths = Get-GitTrackedPaths -SourceRoot $source -GitPath $git.Source
    $sourceAttestation = Get-SourceAttestation -SourceRoot $source -GitPath $git.Source -TrackedPaths $trackedPaths
    $dependencyManifest = Get-DependencyArchiveManifest -SourceRoot $source
    $verifiedParent = Get-VerifiedParentRuntime -ParentRuntime $parent
    $buildWorkspace = $null
    try {
        $buildWorkspace = New-IsolatedBuildWorkspace -WorkspaceBase (Join-Path $env:SystemDrive 'oai-ytdlp-build')
        $buildSource = New-IsolatedBuildSource -SourceRoot $source -WorkspaceRoot $buildWorkspace -DependencyRoots @($dependencyManifest.roots) -TrackedPaths $trackedPaths
        $copiedSourceAttestation = Get-SourceInputAttestation -SourceRoot $buildSource -Commit $sourceAttestation.commit -StatusPorcelain '' -TrackedPaths $trackedPaths
        if ($copiedSourceAttestation.treeSha256 -cne $sourceAttestation.treeSha256 -or $copiedSourceAttestation.trackedFileCount -ne $sourceAttestation.trackedFileCount) { throw 'source_input_changed' }
        $dependencyArchiveSourcePath = Join-Path $DependencyArchiveDirectory $dependencyManifest.name
        if (-not (Test-Path -LiteralPath $dependencyArchiveSourcePath -PathType Leaf)) { throw "Reviewed dependency archive is missing: $dependencyArchiveSourcePath" }
        $dependencyArchivePath = Join-Path $buildWorkspace $dependencyManifest.name
        Copy-Item -LiteralPath $dependencyArchiveSourcePath -Destination $dependencyArchivePath
        Initialize-OfficialDependencies -SourceRoot $buildSource -DependencyArchiveDirectory $buildWorkspace
        $tools = Get-VsBuildTools
        $cmake = Get-CmakeExecutable -VisualStudioInstallation $tools.InstallationPath
        $buildContext = New-HermeticBuildContext -SourceRoot $buildSource -WorkspaceRoot $buildWorkspace -VCToolsVersion $tools.VCToolsVersion -WindowsSdkVersion $tools.WindowsSdkVersion
        $dependencyPlan = Invoke-ReleaseX64Dependencies -SourceRoot $buildSource -MsBuildPath $tools.MsBuildPath -CmakePath $cmake -BuildContext $buildContext
        $linkerInputs = Get-DependencyLibraryAttestation -Plan $dependencyPlan
        $buildSolution = Join-Path $buildSource 'ytdlp-interface\ytdlp-interface.sln'
        $productBuildArguments = @($buildSolution, '/m', '/t:Build') + @($buildContext.MsBuildArguments)
        Invoke-CheckedProcess -FilePath $tools.MsBuildPath -Arguments $productBuildArguments -Name 'Release x64 MSBuild' -NormalizeEnvironment -WorkingDirectory $buildContext.WorkingDirectory -EnvironmentOverrides $buildContext.EnvironmentOverrides | Out-Null
        Assert-DependencyLibraryAttestationUnchanged -Plan $dependencyPlan -Before $linkerInputs | Out-Null
        $attestation = [ordered]@{
            source = $sourceAttestation
            dependencyArchive = [ordered]@{ name = $dependencyManifest.name; sha256 = (Get-FileHash -LiteralPath $dependencyArchivePath -Algorithm SHA256).Hash.ToUpperInvariant() }
            linkerInputs = $linkerInputs
            toolchain = Get-BuildToolchainAttestation -Tools $tools -CmakePath $cmake
            commands = Get-BuildCommandAttestation -SourceRoot $buildSource -DependencyPlan $dependencyPlan -ProductExecutable $tools.MsBuildPath -ProductArguments $productBuildArguments -BuildContext $buildContext
        }
        $product = Join-Path $buildSource 'ytdlp-interface\x64\Release\ytdlp-interface.exe'
        if (-not (Test-Path -LiteralPath $product -PathType Leaf)) { throw "Release x64 product is missing: $product" }
        $candidate = New-CandidateRoot -BaseDirectory $candidateBase
        try {
        Copy-CandidateFile -Source $product -DestinationDirectory $candidate
        foreach ($name in Get-RequiredRuntimeFiles) { Copy-CandidateFile -Source (Join-Path $parent $name) -DestinationDirectory $candidate }
        if ((Get-FileHash -LiteralPath (Join-Path $candidate 'yt-dlp.exe') -Algorithm SHA256).Hash.ToUpperInvariant() -cne $verifiedParent.YtDlpHash) { throw 'Candidate yt-dlp copy hash does not match verified parent runtime.' }
        Copy-CandidateFile -Source $settings -DestinationDirectory $candidate
        Import-Module -Name (Join-Path $buildSource 'tools\runtime-maintenance.psm1') -Force
        RepairSettings -SettingsPath (Join-Path $candidate 'ytdlp-interface.json') -Confirm:$false | Out-Null
        $localeDirectory = Join-Path $candidate 'locales'; [IO.Directory]::CreateDirectory($localeDirectory) | Out-Null
        Copy-CandidateFile -Source (Join-Path $buildSource 'locales\ko-KR.json') -DestinationDirectory $localeDirectory
        Test-CandidateAssembly -CandidateRoot $candidate
        $manifest = Get-CandidateManifest -CandidateRoot $candidate -Attestation $attestation
        $manifestPath = Join-Path $candidate 'candidate-manifest.json'
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        $writtenManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Assert-CandidateManifestSeal -CandidateRoot $candidate -Manifest $writtenManifest | Out-Null
        return [pscustomobject]@{ CandidateRoot = $candidate; ManifestPath = $manifestPath }
        }
        catch { if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue }; throw }
    }
    finally { if (Test-Path -LiteralPath $buildWorkspace) { Remove-Item -LiteralPath $buildWorkspace -Recurse -Force -ErrorAction SilentlyContinue } }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Run) { Write-Output 'No action taken. Re-run with -Run to build and assemble a candidate.' }
    else { Invoke-BuildCandidate -SourceRoot $SourceRoot -ParentRuntime $ParentRuntime -CandidateBase $CandidateBase -DependencyArchiveDirectory $DependencyArchiveDirectory }
}
