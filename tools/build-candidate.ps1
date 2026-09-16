[CmdletBinding()]
param(
    [string] $SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $ParentRuntime,
    [string] $CandidateBase,
    [string] $DependencyArchiveDirectory,
    [string] $RuntimeArchiveDirectory,
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

function Get-Bit7zSourceAttestation {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot)
    $relativePath = 'bit7z\KARON_DEPENDENCY_PROVENANCE.json'
    $path = Join-Path $SourceRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'bit7z dependency provenance is missing.' }
    $provenance = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $patches = @($provenance.packaging.patches)
    $rarPatch = @($patches | Where-Object id -eq 'remove-rar-unrar-sources')
    $cpmPatch = @($patches | Where-Object id -eq 'pin-cpm-bootstrap-offline')
    $cpm = $provenance.cpmBootstrap
    if ($provenance.schemaVersion -ne 1 -or $provenance.bit7z.version -cne '4.1.0' -or
        $provenance.bit7z.commit -cne 'c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742' -or
        $provenance.bit7z.license -cne 'MPL-2.0' -or
        $provenance.bit7z.sourceUrl -cne 'https://github.com/rikyoz/bit7z/archive/c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742.zip' -or
        $provenance.bit7z.sourceSha256 -cne '6AF52B2E1B9895E8F1193728880206326161940E7A961E3162EC39752DBB3379' -or
        $provenance.packaging.sourceTreeStatus -cne 'MPL-2.0-permitted modified subset' -or $patches.Count -ne 2 -or
        $rarPatch.Count -ne 1 -or $rarPatch[0].buildOptions.BIT7Z_DISABLE_RAR -cne 'ON' -or @($rarPatch[0].removedPaths).Count -ne 29 -or
        $cpmPatch.Count -ne 1 -or $cpmPatch[0].path -cne 'cmake/Dependencies.cmake' -or
        $cpmPatch[0].sha256 -cne 'D5B20EF14BB2469C7A94A8B9746C253AAC9FAE9E3206082EC1C3CF7119905D08' -or
        $cpmPatch[0].bootstrapPath -cne 'cmake/CPM_0.42.3.cmake' -or
        $cpmPatch[0].bootstrapSha256 -cne 'A609E875FD532B067174250F6ABBC3DAC22FE2D64869783FB1E80BDA1625C844' -or
        $cpm.version -cne '0.42.3' -or $cpm.tag -cne 'v0.42.3' -or
        $cpm.commit -cne '49acea0d775087ace0522ee4cc5de45e3da094a8' -or
        $cpm.sourceUrl -cne 'https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.42.3/CPM.cmake' -or
        $cpm.sourceSha256 -cne 'A609E875FD532B067174250F6ABBC3DAC22FE2D64869783FB1E80BDA1625C844' -or
        $cpm.path -cne 'cmake/CPM_0.42.3.cmake' -or
        $cpm.repositoryRawUrl -cne 'https://raw.githubusercontent.com/cpm-cmake/CPM.cmake/49acea0d775087ace0522ee4cc5de45e3da094a8/cmake/CPM.cmake' -or
        $cpm.repositoryRawSha256 -cne '3DD51370ACE79FE042E3A223B1EF98FB37D98D93ABA97B72F7CBBCC11D1B38FE' -or
        $provenance.sevenZip.build.options.BIT7Z_DISABLE_RAR -cne 'ON') { throw 'bit7z dependency provenance is invalid.' }
    $bit7zRoot = Join-Path $SourceRoot 'bit7z'
    $bootstrapPath = Join-Path $bit7zRoot ([string]$cpm.path)
    if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) { throw 'bit7z CPM bootstrap is missing.' }
    if ((Get-FileHash -LiteralPath $bootstrapPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$cpm.sourceSha256) { throw 'bit7z CPM bootstrap SHA-256 mismatch.' }
    $dependenciesPath = Join-Path $bit7zRoot ([string]$cpmPatch[0].path)
    if (-not (Test-Path -LiteralPath $dependenciesPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $dependenciesPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$cpmPatch[0].sha256) { throw 'bit7z CPM integration patch SHA-256 mismatch.' }
    return [ordered]@{
        version = $provenance.bit7z.version
        commit = $provenance.bit7z.commit
        license = $provenance.bit7z.license
        sourceUrl = $provenance.bit7z.sourceUrl
        sourceSha256 = $provenance.bit7z.sourceSha256
        sourceTreeStatus = $provenance.packaging.sourceTreeStatus
        provenancePath = $relativePath.Replace('\', '/')
        cpmBootstrap = [ordered]@{
            version = $cpm.version; tag = $cpm.tag; commit = $cpm.commit
            sourceUrl = $cpm.sourceUrl; sourceSha256 = $cpm.sourceSha256; path = $cpm.path
            repositoryRawUrl = $cpm.repositoryRawUrl; repositoryRawSha256 = $cpm.repositoryRawSha256
        }
    }
}

function Get-GitTrackedPaths {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot, [Parameter(Mandatory = $true)] [string] $GitPath)
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $safeDirectory = 'safe.directory=' + $source
    $paths = @(& $GitPath -c $safeDirectory -C $source ls-files --cached 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or $paths.Count -eq 0) { throw 'Git could not enumerate tracked candidate source inputs.' }
    return @($paths)
}

function Test-SafeGitRelativePath {
    param([Parameter(Mandatory = $true)] [string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.IndexOf([char] 0) -ge 0) { return $false }
    $normalized = $Path.Replace('\', '/')
    if ([IO.Path]::IsPathRooted($normalized) -or $normalized -match '^[A-Za-z]:' -or $normalized.StartsWith('/')) { return $false }
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    foreach ($segment in $normalized.Split([char] '/')) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -eq '.' -or $segment -eq '..' -or
            $segment.IndexOfAny($invalid) -ge 0 -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) { return $false }
    }
    return $true
}

function Get-GitTreeEntries {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $GitPath,
        [Parameter(Mandatory = $true)] [string] $Commit
    )
    if ($Commit -notmatch '^[a-fA-F0-9]{40}$') { throw 'source_export_commit_invalid' }
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $safeDirectory = 'safe.directory=' + $source
    try {
        $result = Invoke-CheckedProcess `
            -FilePath $GitPath `
            -Arguments @('-c', $safeDirectory, '-c', 'core.quotepath=false', '-C', $source, 'ls-tree', '-r', '-z', '--full-tree', $Commit) `
            -Name 'Git source tree inventory'
    } catch {
        throw "source_export_inventory_failed: $($_.Exception.Message)"
    }
    $records = @($result.StandardOutput.Split([char[]] @([char] 0), [StringSplitOptions]::RemoveEmptyEntries))
    if ($records.Count -eq 0) { throw 'source_export_inventory_invalid' }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $entries = @()
    foreach ($record in $records) {
        $match = [regex]::Match($record, '\A(?<mode>[0-7]{6}) (?<type>[a-z]+) (?<object>[0-9a-fA-F]{40})\t(?<path>[\s\S]+)\z')
        if (-not $match.Success -or $match.Groups['type'].Value -ne 'blob') { throw 'source_export_inventory_invalid' }
        $relative = $match.Groups['path'].Value.Replace('\', '/')
        if (-not (Test-SafeGitRelativePath -Path $relative) -or -not $seen.Add($relative)) { throw 'source_export_path_invalid' }
        $entries += [pscustomobject]@{
            Path = $relative
            ObjectId = $match.Groups['object'].Value.ToLowerInvariant()
            Mode = $match.Groups['mode'].Value
        }
    }
    return @($entries)
}

function Get-GitBlobObjectId {
    param([Parameter(Mandatory = $true)] [string] $Path)
    $stream = [IO.File]::OpenRead($Path)
    $hasher = [Security.Cryptography.SHA1]::Create()
    try {
        $length = $stream.Length.ToString([Globalization.CultureInfo]::InvariantCulture)
        $header = [Text.Encoding]::ASCII.GetBytes("blob $length`0")
        [void] $hasher.TransformBlock($header, 0, $header.Length, $header, 0)
        $buffer = [byte[]]::new(81920)
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [void] $hasher.TransformBlock($buffer, 0, $read, $buffer, 0)
        }
        [void] $hasher.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return ([BitConverter]::ToString($hasher.Hash)).Replace('-', '').ToLowerInvariant()
    } finally {
        $hasher.Dispose()
        $stream.Dispose()
    }
}

function Expand-GitSourceArchive {
    param(
        [Parameter(Mandatory = $true)] [string] $ArchivePath,
        [Parameter(Mandatory = $true)] [string] $DestinationRoot,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $TrackedEntries
    )
    $archiveFile = [IO.Path]::GetFullPath($ArchivePath)
    $destination = [IO.Path]::GetFullPath($DestinationRoot)
    if (Test-Path -LiteralPath $destination) { throw 'source_export_destination_exists' }

    $expected = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($tracked in @($TrackedEntries)) {
        $relative = [string] $tracked.Path
        $objectId = [string] $tracked.ObjectId
        if (-not (Test-SafeGitRelativePath -Path $relative) -or $objectId -notmatch '^[a-fA-F0-9]{40}$' -or $expected.ContainsKey($relative)) {
            throw 'source_export_inventory_invalid'
        }
        $expected.Add($relative, $tracked)
    }

    $archive = $null
    $createdDestination = $false
    try {
        if (-not (Test-Path -LiteralPath $archiveFile -PathType Leaf)) { throw 'source_export_invalid' }
        try { $archive = [IO.Compression.ZipFile]::OpenRead($archiveFile) }
        catch { throw 'source_export_invalid' }

        [IO.Directory]::CreateDirectory($destination) | Out-Null
        $createdDestination = $true
        $seenEntries = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $seenFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        foreach ($entry in $archive.Entries) {
            $entryName = $entry.FullName.Replace('\', '/')
            $isDirectory = $entryName.EndsWith('/')
            $relative = $(if ($isDirectory) { $entryName.TrimEnd([char] '/') } else { $entryName })
            if (-not (Test-SafeGitRelativePath -Path $relative) -or -not $seenEntries.Add($relative)) { throw 'source_export_path_invalid' }
            $target = [IO.Path]::GetFullPath((Join-Path $destination $relative))
            if (-not (Test-PathContained -Root $destination -Path $target)) { throw 'source_export_path_invalid' }

            if ($isDirectory) {
                [IO.Directory]::CreateDirectory($target) | Out-Null
                continue
            }

            $expectedEntry = $null
            if (-not $expected.TryGetValue($relative, [ref] $expectedEntry) -or $relative -cne [string] $expectedEntry.Path) {
                throw 'source_export_unexpected_entry'
            }
            $parent = Split-Path -Parent $target
            if (-not [string]::IsNullOrWhiteSpace($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
            $inputStream = $entry.Open()
            try {
                $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $inputStream.CopyTo($outputStream) }
                finally { $outputStream.Dispose() }
            } finally {
                $inputStream.Dispose()
            }
            if ((Get-GitBlobObjectId -Path $target) -ne ([string] $expectedEntry.ObjectId).ToLowerInvariant()) {
                throw 'source_export_blob_mismatch'
            }
            [void] $seenFiles.Add($relative)
        }

        if ($seenFiles.Count -ne $expected.Count) { throw 'source_export_inventory_mismatch' }
        foreach ($relative in $expected.Keys) {
            if (-not $seenFiles.Contains($relative)) { throw 'source_export_inventory_mismatch' }
        }
        return $destination
    } catch {
        $failure = $_.Exception.Message
        if ($createdDestination -and [IO.Directory]::Exists($destination)) {
            try { [IO.Directory]::Delete($destination, $true) }
            catch { throw 'source_export_cleanup_failed' }
        }
        if ($failure -like 'source_export_*') { throw $failure }
        throw "source_export_invalid: $failure"
    } finally {
        if ($null -ne $archive) { $archive.Dispose() }
    }
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
    param([Parameter(Mandatory = $true)] [string] $SourceRoot, [string] $GitPath)
    $source = [IO.Path]::GetFullPath($SourceRoot)
    if ([string]::IsNullOrWhiteSpace($GitPath)) {
        $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $git) { throw 'Git is required to attest the candidate source revision.' }
        $GitPath = $git.Source
    }
    if (-not (Test-Path -LiteralPath $GitPath -PathType Leaf)) { throw 'Git executable is missing for source attestation.' }
    $safeDirectory = 'safe.directory=' + $source
    $commit = (& $GitPath -c $safeDirectory -C $source rev-parse --verify 'HEAD^{commit}' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-fA-F0-9]{40}$') { throw 'Git could not verify the candidate source revision.' }
    $tree = (& $GitPath -c $safeDirectory -C $source rev-parse --verify ($commit + '^{tree}') 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $tree -notmatch '^[a-fA-F0-9]{40}$') { throw 'Git could not verify the candidate source tree.' }
    $status = & $GitPath -c $safeDirectory -C $source status --porcelain=v1 --untracked-files=all 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Git could not inspect the candidate source status.' }
    if (-not [string]::IsNullOrWhiteSpace($status)) { throw 'source_worktree_dirty' }
    return [ordered]@{
        commit = $commit.ToLowerInvariant()
        tree = $tree.ToLowerInvariant()
        dirty = $false
    }
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

function Test-RelativeArchivePathSafe {
    param([string] $Path)
    return -not [string]::IsNullOrWhiteSpace($Path) -and -not [IO.Path]::IsPathRooted($Path) -and
        $Path -notmatch '^[A-Za-z]:' -and $Path -notmatch '(^|[/\\])\.\.([/\\]|$)'
}

function ConvertTo-NormalizedRuntimeArchivePath {
    param([Parameter(Mandatory = $true)] [string] $Path)
    if (-not (Test-RelativeArchivePathSafe -Path $Path)) { throw 'runtime_overlay_layout_invalid' }
    $normalized = $Path.Replace('\', '/').TrimEnd('/')
    $segments = @($normalized -split '/')
    if ([string]::IsNullOrWhiteSpace($normalized) -or @($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -ceq '.' }).Count -ne 0) { throw 'runtime_overlay_layout_invalid' }
    return $normalized
}

function Get-RuntimeArchiveEntryRecords {
    param([Parameter(Mandatory = $true)] [AllowEmptyString()] [string[]] $Listing)
    $records = @()
    $current = $null
    foreach ($line in $Listing) {
        if ($line -match '^Path = (.*)$') {
            if ($null -ne $current) { $records += [pscustomobject]$current }
            $current = [ordered]@{ Path = $Matches[1]; IsDirectory = $false; IsLink = $false }
            continue
        }
        if ($null -eq $current) { continue }
        if ($line -ceq 'Folder = +' -or $line -match '^Attributes = .*D') { $current.IsDirectory = $true }
        if ($line -match '^(Symbolic Link|Hard Link) = ') { $current.IsLink = $true }
    }
    if ($null -ne $current) { $records += [pscustomobject]$current }
    if ($records.Count -lt 2) { throw 'runtime_overlay_layout_invalid' }
    return @($records | Select-Object -Skip 1)
}

function Assert-RuntimeArchiveEntryRecords {
    param([Parameter(Mandatory = $true)] [object[]] $Entries)
    if ($Entries.Count -eq 0) { throw 'runtime_overlay_layout_invalid' }
    $seen = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $normalizedEntries = @()
    foreach ($entry in $Entries) {
        $path = ConvertTo-NormalizedRuntimeArchivePath -Path ([string]$entry.Path)
        if ([bool]$entry.IsLink -or $seen.ContainsKey($path)) { throw 'runtime_overlay_layout_invalid' }
        $record = [pscustomobject]@{ Path = $path; IsDirectory = [bool]$entry.IsDirectory }
        $seen.Add($path, $record)
        $normalizedEntries += $record
    }
    foreach ($entry in $normalizedEntries) {
        $segments = @($entry.Path -split '/')
        for ($index = 1; $index -lt $segments.Count; $index++) {
            $ancestor = ($segments[0..($index - 1)] -join '/')
            if ($seen.ContainsKey($ancestor) -and -not [bool]$seen[$ancestor].IsDirectory) { throw 'runtime_overlay_layout_invalid' }
        }
    }
    return @($normalizedEntries)
}

function Assert-NoRuntimeOverlayReparsePoints {
    param([Parameter(Mandatory = $true)] [string] $Root)
    $items = @((Get-Item -LiteralPath $Root -Force)) + @(Get-ChildItem -LiteralPath $Root -Force -Recurse)
    foreach ($item in $items) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'runtime_overlay_layout_invalid' }
    }
}

function Get-RuntimeFileAttestation {
    param([Parameter(Mandatory = $true)] [string] $Root, [Parameter(Mandatory = $true)] [string[]] $Names)
    $rootFull = [IO.Path]::GetFullPath($Root)
    $uniqueNames = @($Names | Sort-Object -Unique)
    $records = @()
    foreach ($name in $uniqueNames) {
        if ([IO.Path]::GetFileName($name) -cne $name) { throw 'runtime_parent_copy_mismatch' }
        $path = Join-Path $rootFull $name
        if (-not (Test-PathContained -Root $rootFull -Path $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'runtime_parent_copy_mismatch' }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'runtime_parent_copy_mismatch' }
        $records += [ordered]@{ name = $name; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant(); length = $item.Length }
    }
    if ($records.Count -ne $uniqueNames.Count) { throw 'runtime_parent_copy_mismatch' }
    return @($records)
}

function Assert-CandidateRuntimePreserved {
    param([Parameter(Mandatory = $true)] [string] $CandidateRoot, [Parameter(Mandatory = $true)] [object[]] $ParentFiles)
    $candidate = [IO.Path]::GetFullPath($CandidateRoot)
    foreach ($expected in $ParentFiles) {
        $path = Join-Path $candidate ([string]$expected.name)
        if (-not (Test-PathContained -Root $candidate -Path $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'runtime_parent_copy_mismatch' }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -ne [long]$expected.length -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() -cne ([string]$expected.sha256).ToUpperInvariant()) { throw 'runtime_parent_copy_mismatch' }
    }
}

function Get-ReleaseRuntimeOverlayDefinitions {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot)
    $requestPath = Join-Path $SourceRoot 'release\requests\v2.19.1-karon.2.json'
    if (-not (Test-Path -LiteralPath $requestPath -PathType Leaf)) { throw 'runtime_overlay_manifest_invalid' }
    $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    if ($request.tag -cne 'v2.19.1-karon.2' -or $null -eq $request.PSObject.Properties['runtimeOverlays']) { throw 'runtime_overlay_manifest_invalid' }
    return @($request.runtimeOverlays)
}

function Assert-RuntimeOverlayManifest {
    param([Parameter(Mandatory = $true)] [object[]] $OverlayDefinitions)
    if ($OverlayDefinitions.Count -ne 2) { throw 'runtime_overlay_manifest_invalid' }
    $ids = @($OverlayDefinitions | ForEach-Object { [string]$_.id } | Sort-Object)
    if (($ids -join ',') -cne 'ffmpeg,sevenZip') { throw 'runtime_overlay_manifest_invalid' }
    $destinations = @($OverlayDefinitions | ForEach-Object { @($_.files) } | ForEach-Object { [string]$_.destination })
    if ($destinations.Count -ne 3 -or (@($destinations | Sort-Object) -join ',') -cne '7z.dll,ffmpeg.exe,ffprobe.exe') { throw 'runtime_overlay_manifest_invalid' }
    foreach ($definition in $OverlayDefinitions) {
        if ([string]::IsNullOrWhiteSpace([string]$definition.archiveName) -or [IO.Path]::GetFileName([string]$definition.archiveName) -cne [string]$definition.archiveName -or
            [string]$definition.archiveSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or @('zip', '7z') -cnotcontains [string]$definition.archiveFormat -or
            [string]::IsNullOrWhiteSpace([string]$definition.expectedVersion)) { throw 'runtime_overlay_manifest_invalid' }
        foreach ($file in @($definition.files)) {
            if (-not (Test-RelativeArchivePathSafe -Path ([string]$file.archivePath)) -or [IO.Path]::GetFileName([string]$file.destination) -cne [string]$file.destination -or
                @('ffmpeg', 'ffprobe', 'sevenZip') -cnotcontains [string]$file.identity) { throw 'runtime_overlay_manifest_invalid' }
        }
        if ($definition.id -ceq 'ffmpeg') {
            $root = [IO.Path]::GetFileNameWithoutExtension([string]$definition.archiveName)
            $mapping = @($definition.files | ForEach-Object { (([string]$_.archivePath).Replace('\', '/')) + '|' + [string]$_.destination + '|' + [string]$_.identity } | Sort-Object)
            if ($definition.archiveFormat -cne 'zip' -or [string]$definition.expectedVersion -cne 'n9.0.1-30-g9258bacca5' -or
                ($mapping -join ',') -cne "$root/bin/ffmpeg.exe|ffmpeg.exe|ffmpeg,$root/bin/ffprobe.exe|ffprobe.exe|ffprobe") { throw 'runtime_overlay_manifest_invalid' }
        }
        elseif ($definition.id -ceq 'sevenZip') {
            $file = @($definition.files)[0]
            if ($definition.archiveFormat -cne '7z' -or [string]$definition.expectedVersion -cne '26.01' -or @($definition.files).Count -ne 1 -or
                (([string]$file.archivePath).Replace('\', '/') + '|' + [string]$file.destination + '|' + [string]$file.identity) -cne 'x64/7z.dll|7z.dll|sevenZip') { throw 'runtime_overlay_manifest_invalid' }
        }
    }
}

function Get-RuntimeOverlayIdentity {
    param(
        [Parameter(Mandatory = $true)] [string] $Identity,
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $ExpectedVersion,
        [scriptblock] $IdentityReader
    )
    $observed = if ($null -ne $IdentityReader) { [string](& $IdentityReader $Identity $Path) }
        elseif ($Identity -ceq 'sevenZip') { [string](Get-Item -LiteralPath $Path).VersionInfo.FileVersion }
        else { Invoke-CheckedExecutable -Path $Path -Arguments @('-version') -Name $Identity }
    if ($Identity -ceq 'sevenZip') {
        if ($observed -cne $ExpectedVersion) { throw 'runtime_overlay_version_mismatch' }
        return $observed
    }
    if (@('ffmpeg', 'ffprobe') -cnotcontains $Identity) { throw 'runtime_overlay_version_mismatch' }
    $firstLine = @($observed -split "`r?`n", 2)[0]
    $pattern = '^' + [regex]::Escape($Identity + ' version ' + $ExpectedVersion) + '(?: .*)?$'
    if ($firstLine -cnotmatch $pattern) { throw 'runtime_overlay_version_mismatch' }
    return $firstLine
}

function Install-ReviewedRuntimeOverlays {
    param(
        [Parameter(Mandatory = $true)] [string] $CandidateRoot,
        [Parameter(Mandatory = $true)] [string] $RuntimeArchiveDirectory,
        [Parameter(Mandatory = $true)] [object[]] $OverlayDefinitions,
        [string] $SevenZipPath,
        [scriptblock] $IdentityReader,
        [scriptblock] $ArchiveCopier,
        [scriptblock] $OverlayCopier,
        [string] $StagingBase = ([IO.Path]::GetTempPath())
    )
    Assert-RuntimeOverlayManifest -OverlayDefinitions $OverlayDefinitions
    $candidate = [IO.Path]::GetFullPath($CandidateRoot)
    $archiveDirectory = [IO.Path]::GetFullPath($RuntimeArchiveDirectory)
    if (-not (Test-Path -LiteralPath $candidate -PathType Container) -or -not (Test-Path -LiteralPath $archiveDirectory -PathType Container)) { throw 'runtime_overlay_layout_invalid' }
    if ([string]::IsNullOrWhiteSpace($SevenZipPath)) { $SevenZipPath = Get-TrustedSevenZip }
    if (-not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) { throw 'runtime_overlay_layout_invalid' }
    $staging = Join-Path ([IO.Path]::GetFullPath($StagingBase)) ('runtime-overlays-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($staging) | Out-Null
    $attestation = @()
    try {
        foreach ($definition in $OverlayDefinitions) {
            $externalArchive = Join-Path $archiveDirectory ([string]$definition.archiveName)
            if (-not (Test-PathContained -Root $archiveDirectory -Path $externalArchive) -or -not (Test-Path -LiteralPath $externalArchive -PathType Leaf)) { throw 'runtime_overlay_layout_invalid' }
            $overlayRoot = Join-Path $staging ([string]$definition.id)
            $archiveStaging = Join-Path $overlayRoot 'archive'
            [IO.Directory]::CreateDirectory($archiveStaging) | Out-Null
            $archive = Join-Path $archiveStaging ([string]$definition.archiveName)
            if ($null -ne $ArchiveCopier) { & $ArchiveCopier $externalArchive $archive } else { Copy-Item -LiteralPath $externalArchive -Destination $archive }
            if (-not (Test-Path -LiteralPath $archive -PathType Leaf) -or ((Get-Item -LiteralPath $archive -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'runtime_overlay_layout_invalid' }
            $archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($archiveHash -cne ([string]$definition.archiveSha256).ToUpperInvariant()) { throw 'runtime_overlay_sha256_mismatch' }
            $listing = (Invoke-CheckedProcess -FilePath $SevenZipPath -Arguments @('l', '-slt', $archive) -Name 'runtime overlay inspection').StandardOutput -split "`r?`n"
            $entries = @(Assert-RuntimeArchiveEntryRecords -Entries (Get-RuntimeArchiveEntryRecords -Listing $listing))
            $entryPaths = @($entries | ForEach-Object { [string]$_.Path })
            $selectedPaths = @($definition.files | ForEach-Object { ConvertTo-NormalizedRuntimeArchivePath -Path ([string]$_.archivePath) })
            foreach ($selectedPath in $selectedPaths) { if ($entryPaths -cnotcontains $selectedPath) { throw 'runtime_overlay_layout_invalid' } }
            $overlayStaging = Join-Path $overlayRoot 'extracted'
            [IO.Directory]::CreateDirectory($overlayStaging) | Out-Null
            $extractionPaths = @($selectedPaths | ForEach-Object { $_.Replace('/', '\') })
            $outputArgument = '-o' + $overlayStaging
            Invoke-CheckedProcess -FilePath $SevenZipPath -Arguments (@('x', $archive) + $extractionPaths + @($outputArgument, '-y')) -Name 'runtime overlay extraction' | Out-Null
            Assert-NoRuntimeOverlayReparsePoints -Root $overlayStaging
            $extracted = @(Get-ChildItem -LiteralPath $overlayStaging -File -Recurse)
            $extractedPaths = @($extracted | ForEach-Object { $_.FullName.Substring($overlayStaging.Length).TrimStart('\', '/').Replace('\', '/') } | Sort-Object)
            if ($extracted.Count -ne $selectedPaths.Count -or ($extractedPaths -join ',') -cne (@($selectedPaths | Sort-Object) -join ',')) { throw 'runtime_overlay_layout_invalid' }
            $fileAttestation = @()
            foreach ($file in @($definition.files)) {
                $source = Join-Path $overlayStaging ([string]$file.archivePath)
                $destination = Join-Path $candidate ([string]$file.destination)
                if (-not (Test-PathContained -Root $overlayStaging -Path $source) -or -not (Test-Path -LiteralPath $source -PathType Leaf) -or
                    -not (Test-PathContained -Root $candidate -Path $destination) -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw 'runtime_overlay_layout_invalid' }
                $identity = Get-RuntimeOverlayIdentity -Identity ([string]$file.identity) -Path $source -ExpectedVersion ([string]$definition.expectedVersion) -IdentityReader $IdentityReader
                $item = Get-Item -LiteralPath $source -Force
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'runtime_overlay_layout_invalid' }
                $sourceRecord = [ordered]@{
                    sourceArchivePath = ConvertTo-NormalizedRuntimeArchivePath -Path ([string]$file.archivePath)
                    destination = [string]$file.destination
                    productIdentity = [string]$file.identity
                    sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToUpperInvariant()
                    length = $item.Length
                    identity = $identity
                }
                if ($null -ne $OverlayCopier) { & $OverlayCopier $source $destination } else { Copy-Item -LiteralPath $source -Destination $destination -Force }
                if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw 'runtime_overlay_destination_mismatch' }
                $destinationItem = Get-Item -LiteralPath $destination -Force
                if (($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $destinationItem.Length -ne [long]$sourceRecord.length -or
                    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$sourceRecord.sha256) { throw 'runtime_overlay_destination_mismatch' }
                $destinationIdentity = Get-RuntimeOverlayIdentity -Identity ([string]$file.identity) -Path $destination -ExpectedVersion ([string]$definition.expectedVersion) -IdentityReader $IdentityReader
                if ($destinationIdentity -cne [string]$sourceRecord.identity) { throw 'runtime_overlay_destination_mismatch' }
                $fileAttestation += $sourceRecord
            }
            $attestation += [ordered]@{ id = [string]$definition.id; archive = [ordered]@{ name = [string]$definition.archiveName; sha256 = $archiveHash }; expectedVersion = [string]$definition.expectedVersion; files = $fileAttestation }
        }
        return @($attestation)
    }
    finally { if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue } }
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
        [Parameter(Mandatory = $true)] [string] $Commit,
        [Parameter(Mandatory = $true)] [string] $GitPath
    )
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $workspace = [IO.Path]::GetFullPath($WorkspaceRoot)
    $isolated = Join-Path $workspace 'source'
    if (Test-Path -LiteralPath $isolated) { throw 'source_export_destination_exists' }
    [IO.Directory]::CreateDirectory($workspace) | Out-Null

    try { $trackedEntries = @(Get-GitTreeEntries -SourceRoot $source -GitPath $GitPath -Commit $Commit) }
    catch { throw "source_export_failed: $($_.Exception.Message)" }
    $archivePath = Join-Path $workspace ('.source-' + [Guid]::NewGuid().ToString('N') + '.zip')
    $safeDirectory = 'safe.directory=' + $source
    try {
        try {
            [void](Invoke-CheckedProcess `
                -FilePath $GitPath `
                -Arguments @('-c', 'core.autocrlf=false', '-c', $safeDirectory, '-C', $source, 'archive', '--format=zip', ('--output=' + $archivePath), $Commit) `
                -Name 'Git immutable source export')
        } catch {
            throw "source_export_failed: $($_.Exception.Message)"
        }
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or (Get-Item -LiteralPath $archivePath).Length -eq 0) {
            throw 'source_export_failed: Git did not create a source archive.'
        }
        return Expand-GitSourceArchive -ArchivePath $archivePath -DestinationRoot $isolated -TrackedEntries $trackedEntries
    } finally {
        if ([IO.File]::Exists($archivePath)) { [IO.File]::Delete($archivePath) }
    }
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
        EnvironmentOverrides = [ordered]@{ PreferredToolArchitecture = 'x64'; PROCESSOR_ARCHITECTURE = 'AMD64' }
        AttestedEnvironment = [ordered]@{ PreferredToolArchitecture = 'x64'; PROCESSOR_ARCHITECTURE = 'AMD64' }
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
            Name = 'bit7z'; SourceDirectory = (Join-Path $source 'bit7z'); FilePath = $CmakePath
            Arguments = @(
                '-S', (Join-Path $source 'bit7z'),
                '-B', (Join-Path $source 'bit7z\out\build\x64-Release'),
                '-G', 'Visual Studio 17 2022',
                '-A', 'x64',
                '-T', 'v143',
                $CmakeVsGlobalsArgument,
                "-DBIT7Z_CUSTOM_7ZIP_PATH=$(Join-Path $source 'bit7z\lib\7zSDK')",
                "-DCPM_DOWNLOAD_LOCATION=$(Join-Path $source 'bit7z\cmake\CPM_0.42.3.cmake')",
                '-DBIT7Z_USE_NATIVE_STRING=ON',
                '-DBIT7Z_PATH_SANITIZATION=ON',
                '-DBIT7Z_REGEX_MATCHING=ON',
                '-DBIT7Z_STATIC_RUNTIME=ON',
                '-DCMAKE_CXX_FLAGS=/utf-8',
                "-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE=$(Join-Path $source 'bit7z\bin\x64')"
            )
            LibraryPath = (Join-Path $source 'bit7z\bin\x64\bit7z.lib')
            BuildArguments = @(
                '--build', (Join-Path $source 'bit7z\out\build\x64-Release'),
                '--config', 'Release',
                '--target', 'bit7z',
                '--', '/m', '/p:PlatformToolset=v143'
            )
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
            BuildArguments = @('--build', $jpegOutput, '--config', 'Release', '--target', 'turbojpeg-static', '--') + @('/m', '/t:Build') + @($CommonMsBuildArguments)
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
        $phase = if ($dependency.BuildArguments.Count -eq 0) { 'build' } else { 'configure' }
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
    $runtimeFiles = Get-RuntimeFileAttestation -Root $parent -Names @('yt-dlp.exe', 'deno.exe')
    return [pscustomobject]@{ Path = $parent; YtDlpHash = $hash; YtDlpVersion = $version.Trim(); Provenance = $provenance; RuntimeFiles = $runtimeFiles }
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
        applicationSourceCommit = $Attestation.source.commit
        applicationSourceTree = $Attestation.source.tree
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
    param([string] $SourceRoot, [string] $ParentRuntime, [string] $CandidateBase, [string] $DependencyArchiveDirectory, [string] $RuntimeArchiveDirectory)
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
    $sourceIdentity = Get-SourceAttestation -SourceRoot $source -GitPath $git.Source
    $trackedEntries = @(Get-GitTreeEntries -SourceRoot $source -GitPath $git.Source -Commit $sourceIdentity.commit)
    $trackedPaths = @($trackedEntries | ForEach-Object { $_.Path })
    $dependencyManifest = Get-DependencyArchiveManifest -SourceRoot $source
    $verifiedParent = Get-VerifiedParentRuntime -ParentRuntime $parent
    $buildWorkspace = $null
    try {
        $buildWorkspace = New-IsolatedBuildWorkspace -WorkspaceBase (Join-Path $env:SystemDrive 'oai-ytdlp-build')
        $buildSource = New-IsolatedBuildSource -SourceRoot $source -WorkspaceRoot $buildWorkspace -DependencyRoots @($dependencyManifest.roots) -Commit $sourceIdentity.commit -GitPath $git.Source
        $sourceInput = Get-SourceInputAttestation -SourceRoot $buildSource -Commit $sourceIdentity.commit -StatusPorcelain '' -TrackedPaths $trackedPaths
        $sourceAttestation = [ordered]@{
            commit = $sourceIdentity.commit
            tree = $sourceIdentity.tree
            dirty = $sourceInput.dirty
            treeSha256 = $sourceInput.treeSha256
            trackedFileCount = $sourceInput.trackedFileCount
        }
        $dependencyArchiveSourcePath = Join-Path $DependencyArchiveDirectory $dependencyManifest.name
        if (-not (Test-Path -LiteralPath $dependencyArchiveSourcePath -PathType Leaf)) { throw "Reviewed dependency archive is missing: $dependencyArchiveSourcePath" }
        $dependencyArchivePath = Join-Path $buildWorkspace $dependencyManifest.name
        Copy-Item -LiteralPath $dependencyArchiveSourcePath -Destination $dependencyArchivePath
        Initialize-OfficialDependencies -SourceRoot $buildSource -DependencyArchiveDirectory $buildWorkspace
        $bit7zSourceAttestation = Get-Bit7zSourceAttestation -SourceRoot $buildSource
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
            dependencyArchive = [ordered]@{
                name = $dependencyManifest.name
                sha256 = (Get-FileHash -LiteralPath $dependencyArchivePath -Algorithm SHA256).Hash.ToUpperInvariant()
                bit7zSource = $bit7zSourceAttestation
            }
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
        $overlayDefinitions = Get-ReleaseRuntimeOverlayDefinitions -SourceRoot $buildSource
        $attestation.runtimeOverlays = Install-ReviewedRuntimeOverlays -CandidateRoot $candidate -RuntimeArchiveDirectory $RuntimeArchiveDirectory -OverlayDefinitions $overlayDefinitions -StagingBase $buildWorkspace
        Assert-CandidateRuntimePreserved -CandidateRoot $candidate -ParentFiles $verifiedParent.RuntimeFiles
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
    else { Invoke-BuildCandidate -SourceRoot $SourceRoot -ParentRuntime $ParentRuntime -CandidateBase $CandidateBase -DependencyArchiveDirectory $DependencyArchiveDirectory -RuntimeArchiveDirectory $RuntimeArchiveDirectory }
}
