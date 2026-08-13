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

function Invoke-CheckedProcess {
    param([Parameter(Mandatory = $true)] [string] $FilePath, [string[]] $Arguments = @(), [Parameter(Mandatory = $true)] [string] $Name)
    $stdoutPath = Join-Path ([IO.Path]::GetTempPath()) ('ytdlp-interface-process-' + [Guid]::NewGuid().ToString('N') + '.out')
    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) ('ytdlp-interface-process-' + [Guid]::NewGuid().ToString('N') + '.err')
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList (ConvertTo-ProcessArgumentLine -Arguments $Arguments) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { [IO.File]::ReadAllText($stdoutPath).Trim() } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { [IO.File]::ReadAllText($stderrPath).Trim() } else { '' }
        if ($process.ExitCode -ne 0) { throw "$Name exited with code $($process.ExitCode). stdout=$stdout stderr=$stderr" }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; StandardOutput = $stdout; StandardError = $stderr }
    }
    finally {
        if (Test-Path -LiteralPath $stdoutPath) { Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
    }
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
    return [pscustomobject]@{ InstallationPath = $installationPath; MsBuildPath = $msbuild; V143Path = $v143 }
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
    if ($missing.Count -eq 0) { return }
    if ([string]::IsNullOrWhiteSpace($DependencyArchiveDirectory)) { throw 'Reviewed dependency archive directory is required for missing dependencies.' }
    $archive = Join-Path $DependencyArchiveDirectory $manifest.name
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Reviewed dependency archive is missing: $archive" }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant() -cne ([string]$manifest.sha256).ToUpperInvariant()) { throw 'Dependency archive SHA-256 does not match the source-controlled manifest.' }
    $sevenZip = Get-TrustedSevenZip
    $listing = (Invoke-CheckedProcess -FilePath $sevenZip -Arguments @('l', '-slt', $archive) -Name '7z dependency inspection').StandardOutput -split "`r?`n"
    $entries = Get-ArchiveEntriesFromListing -Listing $listing
    if ($entries.Count -eq 0) { throw 'Dependency archive contains no inspectable entries.' }
    foreach ($entry in $entries) { if (-not (Test-ArchiveEntrySafe -Entry $entry -ExpectedRoots $roots)) { throw 'Dependency archive contains an unsafe or unexpected entry.' } }
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

function Get-VerifiedParentRuntime {
    param([Parameter(Mandatory = $true)] [string] $ParentRuntime)
    $parent = [IO.Path]::GetFullPath($ParentRuntime)
    $provenancePath = Join-Path $parent 'yt-dlp-provenance.json'
    if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) { throw 'Parent runtime yt-dlp provenance is missing.' }
    $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
    if ($provenance.repository -ne 'yt-dlp/yt-dlp-nightly-builds' -or $provenance.channel -ne 'nightly' -or [string]::IsNullOrWhiteSpace($provenance.tag)) { throw 'Parent runtime provenance is not the official nightly channel.' }
    $ytDlp = Join-Path $parent 'yt-dlp.exe'
    if (-not (Test-Path -LiteralPath $ytDlp -PathType Leaf)) { throw 'Parent runtime yt-dlp.exe is missing.' }
    $hash = (Get-FileHash -LiteralPath $ytDlp -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($hash -cne ([string]$provenance.sha256).ToUpperInvariant()) { throw 'Parent runtime yt-dlp hash does not match provenance.' }
    $version = Invoke-CheckedExecutable -Path $ytDlp -Arguments @('--version') -Name 'yt-dlp'
    if ($version.Trim() -ne ([string]$provenance.tag).Trim()) { throw 'Parent runtime yt-dlp version does not match provenance tag.' }
    foreach ($check in @(@('ffmpeg.exe', '-version', 'ffmpeg'), @('ffprobe.exe', '-version', 'ffprobe'), @('deno.exe', '--version', 'deno'))) {
        Invoke-CheckedExecutable -Path (Join-Path $parent $check[0]) -Arguments @($check[1]) -Name $check[2] | Out-Null
    }
    return [pscustomobject]@{ Path = $parent; YtDlpHash = $hash; YtDlpVersion = $version.Trim(); Provenance = $provenance }
}

function Get-CandidateManifest {
    param([Parameter(Mandatory = $true)] [string] $CandidateRoot)
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
    $verifiedParent = Get-VerifiedParentRuntime -ParentRuntime $parent
    Initialize-OfficialDependencies -SourceRoot $source -DependencyArchiveDirectory $DependencyArchiveDirectory
    $tools = Get-VsBuildTools
    Invoke-CheckedProcess -FilePath $tools.MsBuildPath -Arguments @($solution, '/m', '/t:Build', '/p:Configuration=Release', '/p:Platform=x64') -Name 'Release x64 MSBuild' | Out-Null
    $product = Join-Path $source 'ytdlp-interface\x64\Release\ytdlp-interface.exe'
    if (-not (Test-Path -LiteralPath $product -PathType Leaf)) { throw "Release x64 product is missing: $product" }
    $candidate = New-CandidateRoot -BaseDirectory $candidateBase
    try {
        Copy-CandidateFile -Source $product -DestinationDirectory $candidate
        foreach ($name in Get-RequiredRuntimeFiles) { Copy-CandidateFile -Source (Join-Path $parent $name) -DestinationDirectory $candidate }
        if ((Get-FileHash -LiteralPath (Join-Path $candidate 'yt-dlp.exe') -Algorithm SHA256).Hash.ToUpperInvariant() -cne $verifiedParent.YtDlpHash) { throw 'Candidate yt-dlp copy hash does not match verified parent runtime.' }
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
