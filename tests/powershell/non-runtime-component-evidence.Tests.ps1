$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$collectorPath = Join-Path $repoRoot 'tools\collect-non-runtime-component-evidence.ps1'
$powershellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$utf8NoBom = New-Object Text.UTF8Encoding($false)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-TestSha256 {
    param([Parameter(Mandatory = $true)] [string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-TestText {
    param([string] $Path, [string] $Text)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Write-TestJson {
    param([string] $Path, [object] $Value)
    Write-TestText -Path $Path -Text (($Value | ConvertTo-Json -Depth 40 -Compress) + [char]10)
}

function New-TestZip {
    param([string] $Path, [hashtable] $Entries)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $names = @($Entries.Keys | ForEach-Object { [string]$_ })
            [Array]::Sort($names, [StringComparer]::Ordinal)
            foreach ($name in $names) {
                $entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $entryStream = $entry.Open()
                try {
                    $bytes = [byte[]]$Entries[$name]
                    $entryStream.Write($bytes, 0, $bytes.Length)
                }
                finally { $entryStream.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

function New-TestZipWithRawEntryName {
    param([string] $Path, [string] $EntryName, [byte[]] $Bytes)

    $targetNameBytes = [Text.Encoding]::UTF8.GetBytes($EntryName)
    $containsNonAscii = @($targetNameBytes | Where-Object { $_ -gt 0x7F }).Count -gt 0
    if ($containsNonAscii) {
        $safeName = [char]0x00E9 + ('x' * ($targetNameBytes.Length - 2))
    }
    else {
        $safeName = 'x' * $targetNameBytes.Length
    }
    $safeNameBytes = [Text.Encoding]::UTF8.GetBytes($safeName)
    if ($safeNameBytes.Length -ne $targetNameBytes.Length) { throw 'raw ZIP test name length mismatch' }
    New-TestZipFromEntryList -Path $Path -Entries @([pscustomobject]@{ Name = $safeName; Bytes = $Bytes })

    $archiveBytes = [IO.File]::ReadAllBytes($Path)
    $matches = 0
    for ($offset = 0; $offset -le $archiveBytes.Length - $safeNameBytes.Length; $offset++) {
        $equal = $true
        for ($index = 0; $index -lt $safeNameBytes.Length; $index++) {
            if ($archiveBytes[$offset + $index] -ne $safeNameBytes[$index]) { $equal = $false; break }
        }
        if (-not $equal) { continue }
        [Array]::Copy($targetNameBytes, 0, $archiveBytes, $offset, $targetNameBytes.Length)
        $matches++
        $offset += $safeNameBytes.Length - 1
    }
    if ($matches -ne 2) { throw ('raw ZIP test name occurrence mismatch:' + $matches) }
    [IO.File]::WriteAllBytes($Path, $archiveBytes)
}

function New-TestZipFromEntryList {
    param([string] $Path, [object[]] $Entries)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($item in $Entries) {
                $entry = $archive.CreateEntry([string]$item.Name, [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $entryStream = $entry.Open()
                try {
                    $bytes = [byte[]]$item.Bytes
                    $entryStream.Write($bytes, 0, $bytes.Length)
                }
                finally { $entryStream.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

function New-TestZipFromDirectory {
    param([string] $Path, [string] $SourceDirectory)
    $basePath = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\', '/')
    $basePrefix = $basePath + [IO.Path]::DirectorySeparatorChar
    $entries = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $basePath -File -Recurse)) {
        $fullPath = [IO.Path]::GetFullPath($file.FullName)
        if (-not $fullPath.StartsWith($basePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Fixture file escaped source directory: $fullPath"
        }
        $relative = $fullPath.Substring($basePrefix.Length).Replace('\', '/')
        $entries[$relative] = [IO.File]::ReadAllBytes($file.FullName)
    }
    New-TestZip -Path $Path -Entries $entries
}

function New-FixedLengthTestZip {
    param([string] $Path, [int] $Length)
    New-TestZip -Path $Path -Entries @{ 'self-signed/provenance.json' = [Text.Encoding]::UTF8.GetBytes('{"authority":"self"}') }
    $currentLength = (Get-Item -LiteralPath $Path).Length
    if ($currentLength -gt $Length) { throw "Fixture ZIP exceeds requested length: $currentLength > $Length" }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $padding = New-Object byte[] ($Length - $currentLength)
        $stream.Write($padding, 0, $padding.Length)
    }
    finally { $stream.Dispose() }
}

function Get-TestSevenZipExecutable {
    $sealed = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-5-sevenzip-no-rar\output-final\build-work-3e751a83ca044735b5c3780e64f91df2\upstream\7zip-8c63d71ff886bda90c86db28466287f977374237\CPP\7zip\UI\Console\x64\7z.exe'
    foreach ($candidate in @($env:YTDLP_TEST_7Z_EXE, $sealed)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    $command = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    throw 'A real 7z executable is required for the symlink regression.'
}

function Get-TestOrderedTreeDigest {
    param([string] $Root)
    $basePath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $basePrefix = $basePath + [IO.Path]::DirectorySeparatorChar
    $files = @(Get-ChildItem -LiteralPath $basePath -File -Recurse)
    $rows = New-Object 'Collections.Generic.List[string]'
    foreach ($file in $files) {
        $fullPath = [IO.Path]::GetFullPath($file.FullName)
        if (-not $fullPath.StartsWith($basePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Fixture file escaped digest root: $fullPath"
        }
        $relative = $fullPath.Substring($basePrefix.Length).Replace('\', '/')
        $rows.Add($relative + [char]0 + $file.Length + [char]0 + (Get-TestSha256 $file.FullName).ToLowerInvariant() + [char]10)
    }
    $ordered = $rows.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($ordered -join ''))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-TestOrderedChunkDigest {
    param([byte[]] $Bytes)
    $rows = New-Object 'Collections.Generic.List[string]'
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $chunkSize = 65536
        $index = 0
        for ($offset = 0; $offset -lt $Bytes.Length; $offset += $chunkSize) {
            $length = [Math]::Min($chunkSize, $Bytes.Length - $offset)
            $chunk = New-Object byte[] $length
            [Array]::Copy($Bytes, $offset, $chunk, 0, $length)
            $chunkHash = ([BitConverter]::ToString($sha.ComputeHash($chunk))).Replace('-', '').ToLowerInvariant()
            $rows.Add($index.ToString('D8') + [char]0 + $length + [char]0 + $chunkHash + "`r`n")
            $index++
        }
        $aggregate = [Text.Encoding]::UTF8.GetBytes(($rows -join ''))
        return ([BitConverter]::ToString($sha.ComputeHash($aggregate))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

function Get-TestBytesSha256 {
    param([byte[]] $Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-TestTransformEvidence {
    param([byte[]] $Source, [byte[]] $Target)
    $lfCount = @($Source | Where-Object { $_ -eq 10 }).Count
    $crCount = @($Source | Where-Object { $_ -eq 13 }).Count
    return [ordered]@{
        schemaVersion = 'karon-text-transform/v1'
        algorithm = 'lf-to-crlf'
        sourceSha256 = Get-TestBytesSha256 $Source
        sourceLength = $Source.Length
        targetSha256 = Get-TestBytesSha256 $Target
        targetLength = $Target.Length
        lineFeedCount = $lfCount
        sourceCarriageReturnCount = $crCount
        sourceOrderedChunkSha256 = Get-TestOrderedChunkDigest $Source
        targetOrderedChunkSha256 = Get-TestOrderedChunkDigest $Target
    }
}

function New-TestArtifact {
    param([string] $Id, [string] $Path, [string] $Url, [string] $Format = 'zip', [bool] $Include = $true)
    $file = Get-Item -LiteralPath $Path
    return [ordered]@{
        id = $Id
        fileName = $file.Name
        url = $Url
        sha256 = Get-TestSha256 $file.FullName
        length = $file.Length
        format = $Format
        includeInBundle = $Include
    }
}

function New-ComponentEvidenceFixture {
    param([string] $Name, [switch] $IncludeRarObject)
    $root = Join-Path $TestDrive $Name
    $cache = Join-Path $root 'source-cache'
    $application = Join-Path $root 'application'
    $inputs = Join-Path $root 'inputs'
    [IO.Directory]::CreateDirectory($cache) | Out-Null
    [IO.Directory]::CreateDirectory($application) | Out-Null
    [IO.Directory]::CreateDirectory($inputs) | Out-Null

    $commitA = '1111111111111111111111111111111111111111'
    $commitB = '2222222222222222222222222222222222222222'
    $license = [Text.Encoding]::UTF8.GetBytes("test license`n")
    $sourceHeader = [Text.Encoding]::UTF8.GetBytes("alpha`nbeta`n")
    $targetHeader = [Text.Encoding]::UTF8.GetBytes("alpha`r`nbeta`r`n")

    $archives = [ordered]@{}
    $definitions = @(
        @('bit7z-source.zip', "bit7z-$commitA/LICENSE", $license),
        @('cpm-source.zip', "CPM.cmake-$commitA/LICENSE", $license),
        @('sevenzip-source.zip', "7zip-$commitA/DOC/License.txt", $license),
        @('nana-source.zip', "nana-$commitA/LICENSE", $license),
        @('libpng-source.zip', "libpng-$commitA/LICENSE", $license),
        @('zlib-source.zip', "zlib-$commitA/README", $license),
        @('libjpeg-source.zip', "libjpeg-$commitA/LICENSE.md", $license)
    )
    foreach ($definition in $definitions) {
        $path = Join-Path $cache $definition[0]
        New-TestZip -Path $path -Entries @{ $definition[1] = [byte[]]$definition[2]; ("$($definition[1]).source") = [Text.Encoding]::UTF8.GetBytes('source') }
        $archives[$definition[0]] = $path
    }
    $nlohmannPath = Join-Path $cache 'nlohmann-source.zip'
    New-TestZip -Path $nlohmannPath -Entries @{
        "json-$commitA/LICENSE.MIT" = $license
        "json-$commitA/single_include/nlohmann/json.hpp" = $sourceHeader
    }
    $archives['nlohmann-source.zip'] = $nlohmannPath
    $ytSourcePath = Join-Path $cache 'yt-dlp-source.zip'
    New-TestZip -Path $ytSourcePath -Entries @{
        "yt-dlp-$commitB/LICENSE" = $license
        "yt-dlp-$commitB/THIRD_PARTY_LICENSES.txt" = [Text.Encoding]::UTF8.GetBytes("third party corpus`n")
    }
    $archives['yt-dlp-source.zip'] = $ytSourcePath

    $cpmBootstrapPath = Join-Path $cache 'CPM_0.42.3.cmake'
    Write-TestText $cpmBootstrapPath "set(CURRENT_CPM_VERSION 0.42.3)`n"
    $zlibPackagePath = Join-Path $cache 'zlib.static.1.2.5.nupkg'
    New-TestZip -Path $zlibPackagePath -Entries @{ 'zlib-package.txt' = [Text.Encoding]::UTF8.GetBytes('zlib package') }
    $libpngPackagePath = Join-Path $cache 'libpng.static.1.6.37.nupkg'
    New-TestZip -Path $libpngPackagePath -Entries @{ 'libpng-package.txt' = [Text.Encoding]::UTF8.GetBytes('libpng package') }
    $ytBinaryPath = Join-Path $cache 'yt-dlp.exe'
    [IO.File]::WriteAllBytes($ytBinaryPath, [Text.Encoding]::UTF8.GetBytes('official yt-dlp binary'))
    $ytBinarySha = Get-TestSha256 $ytBinaryPath
    $ytSumsPath = Join-Path $cache 'SHA2-256SUMS'
    Write-TestText $ytSumsPath ($ytBinarySha.ToLowerInvariant() + "  yt-dlp.exe`n")

    Write-TestText (Join-Path $application 'LICENSE.txt') "application license`n"
    [IO.Directory]::CreateDirectory((Join-Path $application 'ytdlp-interface')) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $application 'ytdlp-interface\json.hpp'), $targetHeader)
    [IO.Directory]::CreateDirectory((Join-Path $application 'tools')) | Out-Null
    Write-TestText (Join-Path $application 'tools\build-candidate.ps1') "Write-Output build`n"
    & git -C $application init | Out-Null
    & git -C $application config user.email 'fixture@example.invalid'
    & git -C $application config user.name 'Fixture'
    & git -C $application config core.autocrlf false
    & git -C $application add -- LICENSE.txt ytdlp-interface/json.hpp tools/build-candidate.ps1
    $oldAuthorDate = $env:GIT_AUTHOR_DATE
    $oldCommitterDate = $env:GIT_COMMITTER_DATE
    try {
        $env:GIT_AUTHOR_DATE = '2026-01-01T00:00:00Z'
        $env:GIT_COMMITTER_DATE = '2026-01-01T00:00:00Z'
        & git -C $application commit -m 'fixture' | Out-Null
    }
    finally {
        $env:GIT_AUTHOR_DATE = $oldAuthorDate
        $env:GIT_COMMITTER_DATE = $oldCommitterDate
    }
    $applicationCommit = (& git -C $application rev-parse HEAD).Trim()

    $dependencyTree = Join-Path $root 'dependency-tree'
    $provenance = [ordered]@{
        schemaVersion = 1
        bit7z = [ordered]@{ version = '4.1.0'; commit = $commitA; license = 'MPL-2.0'; sourceSha256 = Get-TestSha256 $archives['bit7z-source.zip'] }
        cpmBootstrap = [ordered]@{ version = '0.42.3'; tag = 'v0.42.3'; commit = $commitA; sourceSha256 = Get-TestSha256 $cpmBootstrapPath }
        sevenZip = [ordered]@{ version = '26.01'; commit = $commitA; license = 'LGPL-2.1-or-later AND BSD-2-Clause AND BSD-3-Clause' }
    }
    Write-TestJson (Join-Path $dependencyTree 'bit7z\KARON_DEPENDENCY_PROVENANCE.json') $provenance
    Write-TestText (Join-Path $dependencyTree 'bit7z\cmake\CPM_0.42.3.cmake') "set(CURRENT_CPM_VERSION 0.42.3)`n"
    Write-TestText (Join-Path $dependencyTree 'bit7z\cmake\Dependencies.cmake') "set(CPM_DOWNLOAD_LOCATION local)`n"
    Write-TestText (Join-Path $dependencyTree 'nana\build\vc2022\nana.vcxproj') '<Project />'
    Write-TestText (Join-Path $dependencyTree 'libpng\libpng.vcxproj') '<Project />'
    [IO.Directory]::CreateDirectory((Join-Path $dependencyTree 'libpng\packages\zlib.static.1.2.5')) | Out-Null
    Copy-Item -LiteralPath $zlibPackagePath -Destination (Join-Path $dependencyTree 'libpng\packages\zlib.static.1.2.5\zlib.static.1.2.5.nupkg')
    [IO.Directory]::CreateDirectory((Join-Path $dependencyTree 'libpng\packages\libpng.static.1.6.37')) | Out-Null
    Copy-Item -LiteralPath $libpngPackagePath -Destination (Join-Path $dependencyTree 'libpng\packages\libpng.static.1.6.37\libpng.static.1.6.37.nupkg')
    Write-TestText (Join-Path $dependencyTree 'libjpeg-turbo-3.1.2\CMakeLists.txt') 'project(jpeg)'
    $dependencyArchivePath = Join-Path $inputs 'dependencies.zip'
    New-TestZipFromDirectory -Path $dependencyArchivePath -SourceDirectory $dependencyTree

    $dllBytes = [Text.Encoding]::UTF8.GetBytes('no rar dll')
    $dllSha = Get-TestBytesSha256 $dllBytes
    $objects = @('7zHandler.obj', '7zRegister.obj', 'ZipHandler.obj', 'ZipRegister.obj')
    if ($IncludeRarObject) { $objects += 'RarHandler.obj' }
    $buildMap = [ordered]@{ schemaVersion = 1; objectCount = $objects.Count; objects = $objects; excludedObjects = @('RarHandler.obj') }
    $buildProvenance = [ordered]@{
        schemaVersion = 1
        product = '7-Zip'
        version = '26.01'
        architecture = 'x64'
        policy = 'no-rar-handlers-or-code'
        source = [ordered]@{ commit = $commitA; archiveSha256 = Get-TestSha256 $archives['sevenzip-source.zip']; patchedArcMakSha256 = ('A' * 64) }
        buildRecipe = [ordered]@{ path = 'tools/build-sevenzip-no-rar.ps1'; sha256 = ('B' * 64); definitionPath = 'sevenzip-no-rar.json'; definitionSha256 = ('C' * 64) }
        buildMap = 'provenance/build-map.json'
        dll = [ordered]@{ archivePath = 'x64/7z.dll'; sha256 = $dllSha; fileVersion = '26.01'; size = $dllBytes.Length }
        licenses = @('COPYING.LGPL-2.1.txt', 'BSD-NOTICES.txt')
    }
    $runtimeArchivePath = Join-Path $inputs 'sevenzip-runtime.zip'
    New-TestZip -Path $runtimeArchivePath -Entries @{
        'x64/7z.dll' = $dllBytes
        'COPYING.LGPL-2.1.txt' = $license
        'BSD-NOTICES.txt' = [Text.Encoding]::UTF8.GetBytes("bsd notices`n")
        'provenance/build-map.json' = [Text.Encoding]::UTF8.GetBytes(($buildMap | ConvertTo-Json -Depth 10 -Compress) + [char]10)
        'provenance/build-provenance.json' = [Text.Encoding]::UTF8.GetBytes(($buildProvenance | ConvertTo-Json -Depth 10 -Compress) + [char]10)
        'provenance/build-commands.log' = [Text.Encoding]::UTF8.GetBytes("nmake PLATFORM=x64`n")
    }
    $sourceArchivePath = Join-Path $inputs 'sevenzip-corresponding-source.zip'
    New-TestZip -Path $sourceArchivePath -Entries @{
        "7zip-$commitA/CPP/7zip/Bundles/Format7zF/Arc.mak" = [Text.Encoding]::UTF8.GetBytes('RAR_OBJS =')
        "7zip-$commitA/CPP/7zip/Archive/Icons/rar.ico" = [byte[]](0, 1, 2, 3)
        "7zip-$commitA/KaronBuild/build-sevenzip-no-rar.ps1" = [Text.Encoding]::UTF8.GetBytes('build')
    }
    $verificationPath = Join-Path $inputs 'sevenzip-verification.json'
    $verification = [ordered]@{
        runtimeArchiveSha256 = Get-TestSha256 $runtimeArchivePath
        dllSha256 = $dllSha
        correspondingSourceArchiveSha256 = Get-TestSha256 $sourceArchivePath
    }
    Write-TestJson $verificationPath $verification

    $candidatePath = Join-Path $inputs 'candidate-manifest.json'
    $candidate = [ordered]@{
        schemaVersion = 1
        attestation = [ordered]@{
            source = [ordered]@{ commit = $applicationCommit; dirty = $false; treeSha256 = ('D' * 64); trackedFileCount = 3 }
            dependencyArchive = [ordered]@{ name = 'dependencies.zip'; sha256 = Get-TestSha256 $dependencyArchivePath }
            linkerInputs = @(
                [ordered]@{ name = 'bit7z'; library = 'bit7z.lib'; sha256 = ('1' * 64); length = 10 },
                [ordered]@{ name = 'Nana'; library = 'nana_v143_Release_x64.lib'; sha256 = ('2' * 64); length = 20 },
                [ordered]@{ name = 'libpng'; library = 'libpng.lib'; sha256 = ('3' * 64); length = 30 },
                [ordered]@{ name = 'libjpeg-turbo'; library = 'turbojpeg-static.lib'; sha256 = ('4' * 64); length = 40 }
            )
        }
        files = @(
            [ordered]@{ path = '7z.dll'; sha256 = $dllSha; length = $dllBytes.Length },
            [ordered]@{ path = 'yt-dlp.exe'; sha256 = $ytBinarySha; length = (Get-Item $ytBinaryPath).Length },
            [ordered]@{ path = 'ytdlp-interface.exe'; sha256 = ('5' * 64); length = 50 }
        )
    }
    Write-TestJson $candidatePath $candidate

    $artifact = {
        param($id, $fileName, $url, $format, $include)
        New-TestArtifact -Id $id -Path (Join-Path $cache $fileName) -Url $url -Format $format -Include $include
    }
    $licenseRef = {
        param($sourceArtifactId, $archivePath, $bytes)
        [ordered]@{ kind = 'archive-entry'; sourceArtifactId = $sourceArtifactId; archivePath = $archivePath; sha256 = Get-TestBytesSha256 $bytes; length = $bytes.Length }
    }
    $componentBase = {
        param($id, $version, $commit, $licenseExpression, $sourceArtifacts, $licenseTexts, $binding)
        [ordered]@{
            id = $id; name = $id; version = $version; sourceRepository = "https://github.com/example/$id"; sourceCommit = $commit
            licenseExpression = $licenseExpression; modified = $false; sourceArtifacts = @($sourceArtifacts); licenseTexts = @($licenseTexts)
            transforms = @(); buildRecipe = [ordered]@{ description = "Build $id"; candidateBinding = $binding }
        }
    }
    $components = @()
    $applicationLicensePath = Join-Path $application 'LICENSE.txt'
    $components += [ordered]@{
        id = 'application'; name = 'application'; version = '2.19.1-karon.2'; sourceRepository = 'https://github.com/KaronLabs/ytdlp-korean-interface'
        sourceCommit = '$APPLICATION_RELEASE_COMMIT'; licenseExpression = 'MIT'; modified = $true; sourceArtifacts = @()
        licenseTexts = @([ordered]@{ kind = 'repository-file'; path = 'LICENSE.txt'; sha256 = Get-TestSha256 $applicationLicensePath; length = (Get-Item $applicationLicensePath).Length })
        transforms = @(); buildRecipe = [ordered]@{ description = 'tools/build-candidate.ps1'; candidateBinding = [ordered]@{ kind = 'application-source'; candidatePath = 'ytdlp-interface.exe' } }
    }
    $bit7zArtifact = & $artifact 'bit7z-source' 'bit7z-source.zip' "https://github.com/example/bit7z/archive/$commitA.zip" 'zip' $true
    $components += & $componentBase 'bit7z' '4.1.0' $commitA 'MPL-2.0' @($bit7zArtifact) @(& $licenseRef 'bit7z-source' "bit7z-$commitA/LICENSE" $license) ([ordered]@{ kind = 'static-linker-input'; library = 'bit7z.lib' })
    $cpmArtifacts = @(
        (& $artifact 'cpm-source' 'cpm-source.zip' "https://github.com/example/cpm/archive/$commitA.zip" 'zip' $true),
        (& $artifact 'cpm-bootstrap' 'CPM_0.42.3.cmake' 'https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.42.3/CPM.cmake' 'text' $true)
    )
    $components += & $componentBase 'cpm' '0.42.3' $commitA 'MIT' $cpmArtifacts @(& $licenseRef 'cpm-source' "CPM.cmake-$commitA/LICENSE" $license) ([ordered]@{ kind = 'build-input'; dependencyPath = 'bit7z/cmake/CPM_0.42.3.cmake' })
    $sevenZipArtifact = & $artifact 'sevenzip-source' 'sevenzip-source.zip' "https://github.com/example/7zip/archive/$commitA.zip" 'zip' $true
    $components += & $componentBase '7zip' '26.01' $commitA 'LGPL-2.1-or-later AND BSD-2-Clause AND BSD-3-Clause' @($sevenZipArtifact) @(
        [ordered]@{ kind = 'task5-runtime-entry'; archivePath = 'COPYING.LGPL-2.1.txt'; sha256 = Get-TestBytesSha256 $license; length = $license.Length },
        [ordered]@{ kind = 'task5-runtime-entry'; archivePath = 'BSD-NOTICES.txt'; sha256 = Get-TestBytesSha256 ([Text.Encoding]::UTF8.GetBytes("bsd notices`n")); length = 12 }
    ) ([ordered]@{ kind = 'candidate-file'; candidatePath = '7z.dll'; sha256 = $dllSha })
    foreach ($id in @('nana', 'libpng', 'zlib', 'libjpeg-turbo')) {
        $fileName = switch ($id) { 'nana' {'nana-source.zip'} 'libpng' {'libpng-source.zip'} 'zlib' {'zlib-source.zip'} default {'libjpeg-source.zip'} }
        $pathInZip = switch ($id) { 'nana' {"nana-$commitA/LICENSE"} 'libpng' {"libpng-$commitA/LICENSE"} 'zlib' {"zlib-$commitA/README"} default {"libjpeg-$commitA/LICENSE.md"} }
        $licenseExpression = switch ($id) { 'nana' {'BSL-1.0'} 'libpng' {'libpng-2.0'} 'zlib' {'Zlib'} default {'BSD-3-Clause AND IJG AND Zlib'} }
        $library = switch ($id) { 'nana' {'nana_v143_Release_x64.lib'} 'libpng' {'libpng.lib'} 'zlib' {'libpng.lib'} default {'turbojpeg-static.lib'} }
        $sourceArtifacts = @(& $artifact "$id-source" $fileName "https://github.com/example/$id/archive/$commitA.zip" 'zip' $true)
        if ($id -eq 'libpng') { $sourceArtifacts += & $artifact 'libpng-package' 'libpng.static.1.6.37.nupkg' 'https://api.nuget.org/v3-flatcontainer/libpng.static/1.6.37/libpng.static.1.6.37.nupkg' 'binary' $true }
        if ($id -eq 'zlib') { $sourceArtifacts += & $artifact 'zlib-package' 'zlib.static.1.2.5.nupkg' 'https://api.nuget.org/v3-flatcontainer/zlib.static/1.2.5/zlib.static.1.2.5.nupkg' 'binary' $true }
        $components += & $componentBase $id '1.0' $commitA $licenseExpression $sourceArtifacts @(& $licenseRef "$id-source" $pathInZip $license) ([ordered]@{ kind = 'static-linker-input'; library = $library })
    }
    $nlohmannArtifact = & $artifact 'nlohmann-source' 'nlohmann-source.zip' "https://github.com/example/json/archive/$commitA.zip" 'zip' $true
    $transform = Get-TestTransformEvidence $sourceHeader $targetHeader
    $transformBytes = [Text.Encoding]::UTF8.GetBytes(($transform | ConvertTo-Json -Compress) + "`r`n")
    $nlohmann = & $componentBase 'nlohmann-json' '3.12.0' $commitA 'MIT' @($nlohmannArtifact) @(& $licenseRef 'nlohmann-source' "json-$commitA/LICENSE.MIT" $license) ([ordered]@{ kind = 'compiled-header'; repositoryPath = 'ytdlp-interface/json.hpp' })
    $nlohmann.modified = $true
    $nlohmann.transforms = @([ordered]@{
        kind = 'lf-to-crlf'; sourceArtifactId = 'nlohmann-source'; sourceArchivePath = "json-$commitA/single_include/nlohmann/json.hpp"
        repositoryPath = 'ytdlp-interface/json.hpp'; sourceSha256 = Get-TestBytesSha256 $sourceHeader; sourceLength = $sourceHeader.Length
        targetSha256 = Get-TestBytesSha256 $targetHeader; targetLength = $targetHeader.Length
        sourceOrderedChunkSha256 = $transform.sourceOrderedChunkSha256; targetOrderedChunkSha256 = $transform.targetOrderedChunkSha256
        lineFeedCount = $transform.lineFeedCount; transformEvidenceSha256 = Get-TestBytesSha256 $transformBytes; transformEvidenceLength = $transformBytes.Length
    })
    $components += $nlohmann
    $ytArtifacts = @(
        (& $artifact 'yt-dlp-source' 'yt-dlp-source.zip' "https://github.com/yt-dlp/yt-dlp/archive/$commitB.zip" 'zip' $true),
        (& $artifact 'yt-dlp-binary' 'yt-dlp.exe' 'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/2026.08.30.232658/yt-dlp.exe' 'binary' $false),
        (& $artifact 'yt-dlp-sums' 'SHA2-256SUMS' 'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/2026.08.30.232658/SHA2-256SUMS' 'text' $true)
    )
    $thirdPartyBytes = [Text.Encoding]::UTF8.GetBytes("third party corpus`n")
    $ytDlp = & $componentBase 'yt-dlp' '2026.08.30.232658' $commitB 'Unlicense AND LicenseRef-yt-dlp-PyInstaller-Third-Party' $ytArtifacts @(
        (& $licenseRef 'yt-dlp-source' "yt-dlp-$commitB/LICENSE" $license),
        (& $licenseRef 'yt-dlp-source' "yt-dlp-$commitB/THIRD_PARTY_LICENSES.txt" $thirdPartyBytes)
    ) ([ordered]@{ kind = 'candidate-file'; candidatePath = 'yt-dlp.exe'; sha256 = $ytBinarySha })
    $ytDlp.binaryProvenance = [ordered]@{ releaseTag = '2026.08.30.232658'; releaseImmutable = $true; assetId = 1; sourceCommit = $commitB; binaryArtifactId = 'yt-dlp-binary'; checksumsArtifactId = 'yt-dlp-sums' }
    $components += $ytDlp

    $embeddedFiles = @()
    foreach ($relative in @(
        'bit7z/KARON_DEPENDENCY_PROVENANCE.json', 'bit7z/cmake/Dependencies.cmake', 'bit7z/cmake/CPM_0.42.3.cmake',
        'nana/build/vc2022/nana.vcxproj', 'libpng/libpng.vcxproj',
        'libpng/packages/zlib.static.1.2.5/zlib.static.1.2.5.nupkg',
        'libpng/packages/libpng.static.1.6.37/libpng.static.1.6.37.nupkg')) {
        $file = Join-Path $dependencyTree $relative.Replace('/', '\')
        $embeddedFiles += [ordered]@{ path = $relative; sha256 = Get-TestSha256 $file; length = (Get-Item $file).Length }
    }
    $roots = @()
    foreach ($relative in @('bit7z', 'nana', 'libpng', 'libjpeg-turbo-3.1.2', 'libpng/packages/zlib.static.1.2.5')) {
        $directory = Join-Path $dependencyTree $relative.Replace('/', '\')
        $files = @(Get-ChildItem -LiteralPath $directory -File -Recurse)
        $roots += [ordered]@{ path = $relative; fileCount = $files.Count; length = [long](($files | Measure-Object Length -Sum).Sum); orderedTreeSha256 = Get-TestOrderedTreeDigest $directory }
    }
    $manifest = [ordered]@{
        schemaVersion = 'karon-non-runtime-component-evidence/v1'
        approvalProfile = 'test-fixture-v1'
        release = [ordered]@{ tag = 'test-fixture'; platform = 'win-x64'; expectedComponentCount = 10; excludedComponents = @('deno', 'ffmpeg') }
        sharedInputs = [ordered]@{
            dependencyArchive = [ordered]@{
                fileName = 'dependencies.zip'; format = 'zip'; sha256 = Get-TestSha256 $dependencyArchivePath; length = (Get-Item $dependencyArchivePath).Length
                provenancePath = 'bit7z/KARON_DEPENDENCY_PROVENANCE.json'; provenanceSha256 = Get-TestSha256 (Join-Path $dependencyTree 'bit7z\KARON_DEPENDENCY_PROVENANCE.json')
                roots = $roots; embeddedFiles = $embeddedFiles
            }
            sevenZipTask5 = [ordered]@{
                format = 'zip'; runtimeArchiveSha256 = Get-TestSha256 $runtimeArchivePath; runtimeArchiveLength = (Get-Item $runtimeArchivePath).Length
                sourceArchiveSha256 = Get-TestSha256 $sourceArchivePath; sourceArchiveLength = (Get-Item $sourceArchivePath).Length
                verificationSha256 = Get-TestSha256 $verificationPath; verificationLength = (Get-Item $verificationPath).Length
                sourceCommit = $commitA; dllSha256 = $dllSha; dllLength = $dllBytes.Length
                buildMapPath = 'provenance/build-map.json'; buildMapSha256 = Get-TestBytesSha256 ([Text.Encoding]::UTF8.GetBytes(($buildMap | ConvertTo-Json -Depth 10 -Compress) + [char]10))
                requiredObjects = @('7zHandler.obj', '7zRegister.obj', 'ZipHandler.obj', 'ZipRegister.obj')
                forbiddenPattern = '(?i)rar'; forbiddenSourcePattern = '(?i)(^|/)(Rar(?:[^/]*\.(?:c|cc|cpp|cxx|h|hh|hpp|hxx))?|unRarLicense\.txt)($|/)'
            }
            candidate = [ordered]@{ requiredLinkerLibraries = @('bit7z.lib', 'nana_v143_Release_x64.lib', 'libpng.lib', 'turbojpeg-static.lib') }
        }
        components = $components
    }
    $manifestPath = Join-Path $root 'component-manifest.json'
    Write-TestJson $manifestPath $manifest
    return [pscustomobject]@{
        Root = $root; Cache = $cache; Application = $application; ApplicationCommit = $applicationCommit; Manifest = $manifestPath
        Candidate = $candidatePath; DependencyArchive = $dependencyArchivePath; RuntimeArchive = $runtimeArchivePath
        SourceArchive = $sourceArchivePath; Verification = $verificationPath; YtDlpBinary = $ytBinaryPath; DependencyTree = $dependencyTree
    }
}

function Set-TestProductionManifest {
    param([object] $Fixture, [scriptblock] $Mutation)
    $relative = 'release/evidence/v2.19.1-karon.2/non-runtime-components.json'
    $source = Join-Path $repoRoot $relative.Replace('/', '\')
    $destination = Join-Path $Fixture.Application $relative.Replace('/', '\')
    $manifest = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
    & $Mutation $manifest
    Write-TestJson -Path $destination -Value $manifest
    & git -C $Fixture.Application add -f -- $relative
    $oldAuthorDate = $env:GIT_AUTHOR_DATE
    $oldCommitterDate = $env:GIT_COMMITTER_DATE
    try {
        $env:GIT_AUTHOR_DATE = '2026-01-02T00:00:00Z'
        $env:GIT_COMMITTER_DATE = '2026-01-02T00:00:00Z'
        & git -C $Fixture.Application commit -m 'mutated production evidence manifest' | Out-Null
    }
    finally {
        $env:GIT_AUTHOR_DATE = $oldAuthorDate
        $env:GIT_COMMITTER_DATE = $oldCommitterDate
    }
    $Fixture.Manifest = $destination
    $Fixture.ApplicationCommit = (& git -C $Fixture.Application rev-parse HEAD).Trim()
}

function Invoke-TestCollector {
    param(
        [object] $Fixture,
        [string] $OutputDirectory,
        [string] $YtDlpBinaryPath = $Fixture.YtDlpBinary,
        [switch] $OmitReleaseBinding,
        [string] $SourceCacheDirectory = $Fixture.Cache,
        [string] $SevenZipExecutable = ''
    )
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $collectorPath,
        '-ManifestPath', $Fixture.Manifest, '-SourceCacheDirectory', $SourceCacheDirectory, '-OutputDirectory', $OutputDirectory,
        '-ApplicationRepository', $Fixture.Application, '-DependencyArchivePath', $Fixture.DependencyArchive,
        '-SevenZipRuntimeArchivePath', $Fixture.RuntimeArchive, '-SevenZipSourceArchivePath', $Fixture.SourceArchive,
        '-SevenZipVerificationPath', $Fixture.Verification, '-YtDlpBinaryPath', $YtDlpBinaryPath
    )
    if (-not $OmitReleaseBinding) {
        $arguments += @('-ApplicationCommit', $Fixture.ApplicationCommit, '-CandidateManifestPath', $Fixture.Candidate)
    }
    if (-not [string]::IsNullOrWhiteSpace($SevenZipExecutable)) { $arguments += @('-SevenZipExecutable', $SevenZipExecutable) }
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $powershellPath @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorActionPreference }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join [Environment]::NewLine) }
}

function Read-TestManifest {
    param([object] $Fixture)
    return Get-Content -LiteralPath $Fixture.Manifest -Raw | ConvertFrom-Json
}

function Save-TestManifest {
    param([object] $Fixture, [object] $Manifest)
    Write-TestJson $Fixture.Manifest $Manifest
}

Describe 'non-runtime component evidence collector' {
    It 'rejects a coordinated self-signed 696-byte dependency archive replacement' {
        $fixture = New-ComponentEvidenceFixture 'coordinated-dependency-replacement'
        $replacement = Join-Path $fixture.Root 'inputs\self-signed-dependencies.zip'
        New-FixedLengthTestZip -Path $replacement -Length 696
        Set-TestProductionManifest -Fixture $fixture -Mutation {
            param($manifest)
            $manifest.sharedInputs.dependencyArchive.fileName = 'self-signed-dependencies.zip'
            $manifest.sharedInputs.dependencyArchive.format = 'zip'
            $manifest.sharedInputs.dependencyArchive.sha256 = Get-TestSha256 $replacement
            $manifest.sharedInputs.dependencyArchive.length = 696
            $manifest.sharedInputs.dependencyArchive.provenancePath = 'self-signed/provenance.json'
            $manifest.sharedInputs.dependencyArchive.provenanceSha256 = ('0' * 64)
            $manifest.sharedInputs.dependencyArchive.roots = @()
            $manifest.sharedInputs.dependencyArchive.embeddedFiles = @()
        }
        $fixture.DependencyArchive = $replacement
        $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory (Join-Path $fixture.Root 'output') -OmitReleaseBinding
        $result.ExitCode | Should Be 1
        (Get-Item -LiteralPath $replacement).Length | Should Be 696
        $blockers = Get-Content -LiteralPath (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw
        $blockers | Should Match 'production_manifest_projection_mismatch'
        $blockers | Should Not Match 'dependency_archive_mismatch'
    }

    It 'rejects a staged source swapped after initial verification but before ZIP creation' {
        $fixture = New-ComponentEvidenceFixture 'staged-source-swap'
        $padding = New-Object byte[] (8MB)
        $random = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $random.GetBytes($padding) }
        finally { $random.Dispose() }
        [IO.File]::WriteAllBytes((Join-Path $fixture.DependencyTree 'padding.bin'), $padding)
        Remove-Item -LiteralPath $fixture.DependencyArchive -Force
        New-TestZipFromDirectory -Path $fixture.DependencyArchive -SourceDirectory $fixture.DependencyTree
        $manifest = Read-TestManifest $fixture
        $manifest.sharedInputs.dependencyArchive.sha256 = Get-TestSha256 $fixture.DependencyArchive
        $manifest.sharedInputs.dependencyArchive.length = (Get-Item -LiteralPath $fixture.DependencyArchive).Length
        Save-TestManifest $fixture $manifest
        $candidate = Get-Content -LiteralPath $fixture.Candidate -Raw | ConvertFrom-Json
        $candidate.attestation.dependencyArchive.sha256 = Get-TestSha256 $fixture.DependencyArchive
        Write-TestJson $fixture.Candidate $candidate
        $replacement = Join-Path $fixture.Root 'replacement-source.bin'
        $sourceLength = (Get-Item -LiteralPath (Join-Path $fixture.Cache 'bit7z-source.zip')).Length
        [IO.File]::WriteAllBytes($replacement, [byte[]](,0x5A * $sourceLength))
        $privateTemp = Join-Path $fixture.Root 'private-temp'
        [IO.Directory]::CreateDirectory($privateTemp) | Out-Null
        $outputDirectory = Join-Path $fixture.Root 'output'
        $job = Start-Job -ScriptBlock {
            param($TempRoot, $OutputDirectory, $Replacement)
            $deadline = [DateTime]::UtcNow.AddSeconds(45)
            while ([DateTime]::UtcNow -lt $deadline) {
                if (Test-Path -LiteralPath (Join-Path $OutputDirectory 'source-cache-inventory.json')) {
                    $source = Get-ChildItem -LiteralPath $TempRoot -Directory -Filter 'karon-component-evidence-staging-*' -ErrorAction SilentlyContinue |
                        ForEach-Object { Join-Path $_.FullName 'sources\bit7z-source.zip' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
                    if ($null -ne $source) { Copy-Item -LiteralPath $Replacement -Destination $source -Force; return "swapped:$source" }
                }
                Start-Sleep -Milliseconds 5
            }
            return 'swap-timeout'
        } -ArgumentList $privateTemp, $outputDirectory, $replacement
        $oldTemp = $env:TEMP; $oldTmp = $env:TMP
        try {
            $env:TEMP = $privateTemp; $env:TMP = $privateTemp
            $result = Invoke-TestCollector $fixture $outputDirectory
            Wait-Job -Job $job -Timeout 50 | Out-Null
            $jobResult = Receive-Job -Job $job
        }
        finally {
            $env:TEMP = $oldTemp; $env:TMP = $oldTmp
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        $jobResult | Should Match '^swapped:'
        $result.ExitCode | Should Be 1
        (Test-Path -LiteralPath (Join-Path $outputDirectory 'test-fixture-non-runtime-component-evidence.zip')) | Should Be $false
        @(Get-ChildItem -LiteralPath $outputDirectory -Filter '*.partial.*' -File -ErrorAction SilentlyContinue).Count | Should Be 0
    }

    It 'rejects exact production manifest semantic projection mutations' {
        $mutations = @(
            [pscustomobject]@{ Name = 'component-id-casing'; Apply = { param($m) ($m.components | Where-Object id -eq 'nana').id = 'Nana' } },
            [pscustomobject]@{ Name = 'license-text'; Apply = { param($m) ($m.components | Where-Object id -eq 'nana').licenseTexts[0].sha256 = ('0' * 64) } },
            [pscustomobject]@{ Name = 'transform'; Apply = { param($m) ($m.components | Where-Object id -eq 'bit7z').transforms[0].orderedTreeSha256 = ('0' * 64) } },
            [pscustomobject]@{ Name = 'build-recipe'; Apply = { param($m) ($m.components | Where-Object id -eq 'bit7z').buildRecipe.description += ' forged' } },
            [pscustomobject]@{ Name = 'required-linker-libraries'; Apply = { param($m) [array]::Reverse($m.sharedInputs.candidate.requiredLinkerLibraries) } }
        )
        foreach ($mutation in $mutations) {
            $fixture = New-ComponentEvidenceFixture ('projection-' + $mutation.Name)
            Set-TestProductionManifest -Fixture $fixture -Mutation $mutation.Apply
            $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory (Join-Path $fixture.Root 'output') -OmitReleaseBinding
            $result.ExitCode | Should Be 1
            (Get-Content -LiteralPath (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'production_manifest_projection_mismatch'
        }
    }

    It 'accepts the exact approved production manifest projection committed at the required path' {
        $fixture = New-ComponentEvidenceFixture 'approved-production-projection'
        Set-TestProductionManifest -Fixture $fixture -Mutation { param($manifest) }
        $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory (Join-Path $fixture.Root 'output') -OmitReleaseBinding
        $result.ExitCode | Should Be 1
        $blockers = Get-Content -LiteralPath (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw
        $blockers | Should Not Match 'production_manifest_path_invalid'
        $blockers | Should Not Match 'production_manifest_git_blob_mismatch'
        $blockers | Should Not Match 'production_manifest_projection_mismatch'
    }

    It 'rejects a real 7z symlink reported with Attributes AL' {
        $fixture = New-ComponentEvidenceFixture 'sevenzip-symlink-al'
        $sevenZip = Get-TestSevenZipExecutable
        $linkRoot = Join-Path $fixture.Root 'link-source'
        [IO.Directory]::CreateDirectory($linkRoot) | Out-Null
        Write-TestText (Join-Path $linkRoot 'target.txt') 'target'
        New-Item -ItemType SymbolicLink -Path (Join-Path $linkRoot 'link.txt') -Target (Join-Path $linkRoot 'target.txt') | Out-Null
        $archivePath = Join-Path $fixture.Cache 'bit7z-source.7z'
        Push-Location $linkRoot
        try { & $sevenZip 'a' '-snl' '-bd' '-y' $archivePath 'link.txt' | Out-Null }
        finally { Pop-Location }
        $listing = @(& $sevenZip 'l' '-slt' '-ba' $archivePath 2>&1) -join [Environment]::NewLine
        $listing | Should Match '(?m)^Attributes = AL\r?$'
        $manifest = Read-TestManifest $fixture
        $artifact = ($manifest.components | Where-Object id -eq 'bit7z').sourceArtifacts[0]
        $artifact.fileName = 'bit7z-source.7z'; $artifact.format = '7z'; $artifact.sha256 = Get-TestSha256 $archivePath; $artifact.length = (Get-Item $archivePath).Length
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory (Join-Path $fixture.Root 'output') -SevenZipExecutable $sevenZip
        $result.ExitCode | Should Be 1
        (Get-Content -LiteralPath (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'source_archive_preflight_failed:bit7z-source:archive_link_or_reparse_entry'
    }

    It 'accepts normal nested paths emitted by real 7z with backslash separators' {
        $fixture = New-ComponentEvidenceFixture 'sevenzip-normal-nested-path'
        $sevenZip = Get-TestSevenZipExecutable
        $archiveRoot = Join-Path $fixture.Root 'normal-archive-source'
        Write-TestText (Join-Path $archiveRoot 'nested\file.txt') 'normal'
        $archivePath = Join-Path $fixture.Cache 'bit7z-source.7z'
        Push-Location $archiveRoot
        try { & $sevenZip 'a' '-bd' '-y' $archivePath 'nested\file.txt' | Out-Null }
        finally { Pop-Location }
        $listing = @(& $sevenZip 'l' '-slt' '-ba' $archivePath 2>&1) -join [Environment]::NewLine
        $listing | Should Match '(?m)^Path = nested\\file\.txt\r?$'
        $manifest = Read-TestManifest $fixture
        $artifact = ($manifest.components | Where-Object id -eq 'bit7z').sourceArtifacts[0]
        $artifact.fileName = 'bit7z-source.7z'; $artifact.format = '7z'; $artifact.sha256 = Get-TestSha256 $archivePath; $artifact.length = (Get-Item $archivePath).Length
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory (Join-Path $fixture.Root 'output') -SevenZipExecutable $sevenZip
        $result.ExitCode | Should Be 1
        (Get-Content -LiteralPath (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Not Match 'source_archive_preflight_failed:bit7z-source:archive_entry_path_invalid'
    }

    It 'rejects forbidden Windows leaves and archive segments using one canonical policy' {
        $fixture = New-ComponentEvidenceFixture 'windows-segment-policy'
        $manifest = Read-TestManifest $fixture
        $component = $manifest.components | Where-Object id -eq 'bit7z'
        $forbidden = @(
            'CON.txt', 'PRN.ext', 'AUX.bin', 'NUL.dat', 'COM1.txt', 'LPT9.txt',
            ('COM' + [char]0x00B9 + '.txt'), ('COM' + [char]0x00B2 + '.txt'), ('COM' + [char]0x00B3 + '.txt'),
            ('LPT' + [char]0x00B9 + '.txt'), ('LPT' + [char]0x00B2 + '.txt'), ('LPT' + [char]0x00B3 + '.txt'),
            'CONIN$.txt', 'CONOUT$.txt', 'bad<name.txt', 'bad>name.txt', 'bad"name.txt', 'bad|name.txt', 'bad?name.txt', 'bad*name.txt',
            'segment.', 'segment ', '.', '..'
        )
        $index = 0
        foreach ($name in $forbidden) {
            $id = 'invalid-leaf-' + $index.ToString('D2')
            $component.sourceArtifacts += [pscustomobject]@{ id = $id; fileName = $name; url = 'https://github.com/example/windows/archive/1111111111111111111111111111111111111111.zip'; sha256 = ('0' * 64); length = 1; format = 'text'; includeInBundle = $false }
            $index++
        }
        $index = 0
        foreach ($segment in $forbidden) {
            $id = 'invalid-segment-' + $index.ToString('D2')
            $fileName = $id + '.zip'
            $path = Join-Path $fixture.Cache $fileName
            New-TestZipWithRawEntryName -Path $path -EntryName "root/$segment/payload.txt" -Bytes ([Text.Encoding]::UTF8.GetBytes('x'))
            $component.sourceArtifacts += New-TestArtifact -Id $id -Path $path -Url 'https://github.com/example/windows/archive/1111111111111111111111111111111111111111.zip' -Format 'zip' -Include $false
            $index++
        }
        $unicodePath = Join-Path $fixture.Cache 'unicode-normalization-collision.zip'
        New-TestZipFromEntryList -Path $unicodePath -Entries @(
            [pscustomobject]@{ Name = "root/CAF$([char]0x00C9).txt"; Bytes = [Text.Encoding]::UTF8.GetBytes('a') },
            [pscustomobject]@{ Name = "root/cafe$([char]0x0301).txt"; Bytes = [Text.Encoding]::UTF8.GetBytes('b') }
        )
        $component.sourceArtifacts += New-TestArtifact -Id 'unicode-normalization-collision' -Path $unicodePath -Url 'https://github.com/example/windows/archive/1111111111111111111111111111111111111111.zip' -Format 'zip' -Include $false
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        $blockerPath = Join-Path $fixture.Root 'output\non-runtime-component-blockers.json'
        if (-not (Test-Path -LiteralPath $blockerPath -PathType Leaf)) { throw $result.Output }
        $blockers = Get-Content -LiteralPath $blockerPath -Raw
        for ($i = 0; $i -lt $forbidden.Count; $i++) {
            $blockers | Should Match ('source_artifact_file_name_invalid:invalid-leaf-' + $i.ToString('D2'))
            $blockers | Should Match ('source_archive_preflight_failed:invalid-segment-' + $i.ToString('D2'))
        }
        $blockers | Should Match 'source_archive_preflight_failed:unicode-normalization-collision'
    }

    It 'does not delete a replacement staging directory during cleanup' {
        $fixture = New-ComponentEvidenceFixture 'staging-cleanup-identity'
        $privateTemp = Join-Path $fixture.Root 'private-temp'
        [IO.Directory]::CreateDirectory($privateTemp) | Out-Null
        $job = Start-Job -ScriptBlock {
            param($TempRoot)
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            while ([DateTime]::UtcNow -lt $deadline) {
                $directory = Get-ChildItem -LiteralPath $TempRoot -Directory -Filter 'karon-component-evidence-staging-*' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $directory) {
                    Remove-Item -LiteralPath $directory.FullName -Recurse -Force
                    [IO.Directory]::CreateDirectory($directory.FullName) | Out-Null
                    [IO.File]::WriteAllText((Join-Path $directory.FullName 'attacker-owned.txt'), 'replacement')
                    return $directory.FullName
                }
                Start-Sleep -Milliseconds 5
            }
            return 'replacement-timeout'
        } -ArgumentList $privateTemp
        $oldTemp = $env:TEMP; $oldTmp = $env:TMP
        try {
            $env:TEMP = $privateTemp; $env:TMP = $privateTemp
            $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory (Join-Path $fixture.Root 'output') -OmitReleaseBinding
            Wait-Job -Job $job -Timeout 35 | Out-Null
            $replacementPath = Receive-Job -Job $job
        }
        finally {
            $env:TEMP = $oldTemp; $env:TMP = $oldTmp
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        $replacementPath | Should Not Be 'replacement-timeout'
        (Test-Path -LiteralPath (Join-Path $replacementPath 'attacker-owned.txt') -PathType Leaf) | Should Be $true
        Remove-Item -LiteralPath $replacementPath -Recurse -Force
    }

    It 'rejects a tampered immutable source cache artifact' {
        $fixture = New-ComponentEvidenceFixture 'tampered-source'
        [IO.File]::AppendAllText((Join-Path $fixture.Cache 'bit7z-source.zip'), 'tamper')
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'source_hash_mismatch:bit7z-source'
    }

    It 'rejects a missing exact license text entry' {
        $fixture = New-ComponentEvidenceFixture 'missing-license'
        $manifest = Read-TestManifest $fixture
        ($manifest.components | Where-Object id -eq 'bit7z').licenseTexts[0].archivePath = 'missing/LICENSE'
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'license_entry_missing:bit7z'
    }

    It 'rejects a mutable source URL before collecting bytes' {
        $fixture = New-ComponentEvidenceFixture 'mutable-url'
        $manifest = Read-TestManifest $fixture
        ($manifest.components | Where-Object id -eq 'bit7z').sourceArtifacts[0].url = 'https://github.com/example/bit7z/archive/main.zip'
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'mutable_source_url:bit7z-source'
    }

    It 'rejects a nlohmann transform evidence mismatch' {
        $fixture = New-ComponentEvidenceFixture 'nlohmann-mismatch'
        $manifest = Read-TestManifest $fixture
        ($manifest.components | Where-Object id -eq 'nlohmann-json').transforms[0].transformEvidenceSha256 = ('0' * 64)
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'nlohmann_transform_mismatch'
    }

    It 'rejects a preserved yt-dlp binary that differs from the official asset' {
        $fixture = New-ComponentEvidenceFixture 'yt-dlp-mismatch'
        $wrongBinary = Join-Path $fixture.Root 'wrong-yt-dlp.exe'
        [IO.File]::WriteAllBytes($wrongBinary, [Text.Encoding]::UTF8.GetBytes('wrong binary'))
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output') $wrongBinary
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'yt_dlp_binary_mismatch'
    }

    It 'rejects Task 5 evidence containing a RAR object' {
        $fixture = New-ComponentEvidenceFixture 'rar-evidence' -IncludeRarObject
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'sevenzip_rar_evidence_mismatch'
    }

    It 'rejects case-insensitive source cache name collisions' {
        $fixture = New-ComponentEvidenceFixture 'case-collision'
        $manifest = Read-TestManifest $fixture
        ($manifest.components | Where-Object id -eq 'cpm').sourceArtifacts[0].fileName = 'BIT7Z-SOURCE.ZIP'
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'source_cache_name_collision'
    }

    It 'rejects forged Nana component and source provenance' {
        $fixture = New-ComponentEvidenceFixture 'forged-nana-provenance'
        $manifest = Read-TestManifest $fixture
        $nana = $manifest.components | Where-Object id -eq 'nana'
        $nana.version = '9.9.9'
        $nana.sourceRepository = 'https://github.com/forged/nana'
        $nana.sourceCommit = '3333333333333333333333333333333333333333'
        $nana.sourceArtifacts[0].url = 'https://github.com/forged/nana/archive/3333333333333333333333333333333333333333.zip'
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'component_approval_mismatch:nana'
    }

    It 'rejects a source artifact file name that escapes the cache root' {
        $fixture = New-ComponentEvidenceFixture 'source-file-name-traversal'
        Copy-Item -LiteralPath (Join-Path $fixture.Cache 'bit7z-source.zip') -Destination (Join-Path $fixture.Root 'escape.zip')
        $manifest = Read-TestManifest $fixture
        ($manifest.components | Where-Object id -eq 'bit7z').sourceArtifacts[0].fileName = '../escape.zip'
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'source_artifact_file_name_invalid:bit7z-source'
    }

    It 'rejects a source cache directory junction' {
        $fixture = New-ComponentEvidenceFixture 'source-cache-junction'
        $junction = Join-Path $fixture.Root 'source-cache-junction-link'
        New-Item -ItemType Junction -Path $junction -Target $fixture.Cache | Out-Null
        $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory (Join-Path $fixture.Root 'output') -SourceCacheDirectory $junction
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'unsafe_reparse_path:source-cache'
    }

    It 'rejects a source ZIP containing traversal and case-insensitive duplicate entries' {
        $fixture = New-ComponentEvidenceFixture 'malicious-source-zip'
        $manifest = Read-TestManifest $fixture
        $artifact = ($manifest.components | Where-Object id -eq 'bit7z').sourceArtifacts[0]
        $archivePath = Join-Path $fixture.Cache $artifact.fileName
        Remove-Item -LiteralPath $archivePath -Force
        $licensePath = ($manifest.components | Where-Object id -eq 'bit7z').licenseTexts[0].archivePath
        New-TestZipFromEntryList -Path $archivePath -Entries @(
            [pscustomobject]@{ Name = $licensePath; Bytes = [Text.Encoding]::UTF8.GetBytes("test license`n") },
            [pscustomobject]@{ Name = '../escape.txt'; Bytes = [Text.Encoding]::UTF8.GetBytes('escape') },
            [pscustomobject]@{ Name = 'Case.txt'; Bytes = [Text.Encoding]::UTF8.GetBytes('upper') },
            [pscustomobject]@{ Name = 'case.txt'; Bytes = [Text.Encoding]::UTF8.GetBytes('lower') }
        )
        $artifact.sha256 = Get-TestSha256 $archivePath
        $artifact.length = (Get-Item -LiteralPath $archivePath).Length
        Save-TestManifest $fixture $manifest
        $result = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output')
        $result.ExitCode | Should Be 1
        (Get-Content (Join-Path $fixture.Root 'output\non-runtime-component-blockers.json') -Raw) | Should Match 'source_archive_preflight_failed:bit7z-source'
    }

    It 'emits deterministic blockers while final release binding is unavailable' {
        $fixture = New-ComponentEvidenceFixture 'release-binding-blockers'
        $outputDirectory = Join-Path $fixture.Root 'output'
        $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory $outputDirectory -OmitReleaseBinding
        $result.ExitCode | Should Be 1
        $blockerPath = Join-Path $outputDirectory 'non-runtime-component-blockers.json'
        (Test-Path -LiteralPath $blockerPath) | Should Be $true
        $document = Get-Content -LiteralPath $blockerPath -Raw | ConvertFrom-Json
        if (@($document.blockers).Count -ne 2) { throw ($document | ConvertTo-Json -Depth 20 -Compress) }
        @($document.blockers).Count | Should Be 2
        (@($document.blockers) -contains 'application_release_commit_required') | Should Be $true
        (@($document.blockers) -contains 'candidate_manifest_required') | Should Be $true
        (Test-Path -LiteralPath (Join-Path $outputDirectory 'test-fixture-non-runtime-component-evidence.zip')) | Should Be $false
    }

    It 'creates byte-identical evidence bundles for the same closed inputs' {
        $fixture = New-ComponentEvidenceFixture 'positive'
        $first = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output-a')
        $second = Invoke-TestCollector $fixture (Join-Path $fixture.Root 'output-b')
        if ($first.ExitCode -ne 0) {
            $blockerPath = Join-Path $fixture.Root 'output-a\non-runtime-component-blockers.json'
            $blockers = if (Test-Path -LiteralPath $blockerPath) { Get-Content -LiteralPath $blockerPath -Raw } else { 'blocker file missing' }
            $archive = [IO.Compression.ZipFile]::OpenRead($fixture.DependencyArchive)
            try { $entryNames = @($archive.Entries | ForEach-Object { $_.FullName }) -join ',' }
            finally { $archive.Dispose() }
            throw ($first.Output + [Environment]::NewLine + $blockers + [Environment]::NewLine + 'fixture entries=' + $entryNames)
        }
        $first.ExitCode | Should Be 0
        $second.ExitCode | Should Be 0
        $bundleA = Join-Path $fixture.Root 'output-a\test-fixture-non-runtime-component-evidence.zip'
        $bundleB = Join-Path $fixture.Root 'output-b\test-fixture-non-runtime-component-evidence.zip'
        (Test-Path -LiteralPath $bundleA) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $fixture.Root 'output-a\non-runtime-component-blockers.json')) | Should Be $false
        (Get-TestSha256 $bundleA) | Should Be (Get-TestSha256 $bundleB)
    }
    It 'rejects the exact 64 MiB candidate replacement race after inventory' {
        $fixture = New-ComponentEvidenceFixture 'candidate-race-64mib'
        $raceOutput = Join-Path $fixture.Root 'output'
        $raceTemp = Join-Path $fixture.Root 'private-temp'
        [void](New-Item -ItemType Directory -Path $raceTemp -Force)

        $validCandidateBytes = [System.IO.File]::ReadAllBytes($fixture.Candidate)
        $candidateLength = [int64](64MB)
        $candidateStream = [System.IO.File]::Open($fixture.Candidate, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $candidateStream.Write($validCandidateBytes, 0, $validCandidateBytes.Length)
            $spaces = [Text.Encoding]::ASCII.GetBytes((' ' * 64KB))
            $remaining = $candidateLength - $validCandidateBytes.Length
            while ($remaining -gt 0) {
                $count = [int][Math]::Min([int64]$spaces.Length, $remaining)
                $candidateStream.Write($spaces, 0, $count)
                $remaining -= $count
            }
            $candidateStream.Flush($true)
        }
        finally {
            $candidateStream.Dispose()
        }
        $originalCandidateSha256 = Get-TestSha256 $fixture.Candidate

        $forgedCandidateBytes = [System.Text.Encoding]::UTF8.GetBytes('{"forgedAfterValidation":true}')
        $forgedCandidatePath = Join-Path $fixture.Root 'forged-candidate-manifest.json'
        [System.IO.File]::WriteAllBytes($forgedCandidatePath, $forgedCandidateBytes)
        $forgedCandidateSha256 = Get-TestBytesSha256 $forgedCandidateBytes

        $signalPath = Join-Path $raceOutput '.candidate-after-inventory.signal'
        $continuePath = Join-Path $raceOutput '.candidate-after-inventory.continue'
        $inventoryPath = Join-Path $raceOutput 'source-cache-inventory.json'
        $swapJob = Start-Job -ArgumentList @($signalPath, $continuePath, $inventoryPath, $raceTemp, $forgedCandidatePath) -ScriptBlock {
            param($SignalPath, $ContinuePath, $InventoryPath, $RaceTemp, $ForgedCandidatePath)

            $deadline = [DateTime]::UtcNow.AddSeconds(45)
            $stagedCandidatePath = $null
            while (-not [System.IO.File]::Exists($SignalPath) -and -not [System.IO.File]::Exists($InventoryPath)) {
                if ([DateTime]::UtcNow -ge $deadline) { throw '64 MiB candidate race synchronization timeout' }
                if ($null -eq $stagedCandidatePath) {
                    $candidate = Get-ChildItem -LiteralPath $RaceTemp -Recurse -File -Filter 'candidate-manifest.json' -ErrorAction SilentlyContinue |
                        Where-Object { $_.FullName -like '*karon-component-evidence-staging-*' } |
                        Select-Object -First 1
                    if ($null -ne $candidate) { $stagedCandidatePath = $candidate.FullName }
                }
                Start-Sleep -Milliseconds 5
            }

            if (-not [System.IO.File]::Exists($SignalPath)) {
                $hookDeadline = [DateTime]::UtcNow.AddMilliseconds(150)
                while (-not [System.IO.File]::Exists($SignalPath) -and [DateTime]::UtcNow -lt $hookDeadline) {
                    Start-Sleep -Milliseconds 5
                }
            }

            $mode = 'fallback'
            if ([System.IO.File]::Exists($SignalPath)) {
                $mode = 'hook'
                $stagedCandidatePath = [System.IO.File]::ReadAllText($SignalPath).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($stagedCandidatePath)) { throw 'staged 64 MiB candidate was not observed' }

            [System.IO.File]::WriteAllBytes($stagedCandidatePath, [System.IO.File]::ReadAllBytes($ForgedCandidatePath))
            if ($mode -eq 'hook') { [System.IO.File]::WriteAllText($ContinuePath, 'continue') }
            "$mode|$stagedCandidatePath"
        }

        $previousTemp = $env:TEMP
        $previousTmp = $env:TMP
        $previousHook = $env:KARON_EVIDENCE_INTERNAL_TEST_HOOK
        try {
            $env:TEMP = $raceTemp
            $env:TMP = $raceTemp
            $env:KARON_EVIDENCE_INTERNAL_TEST_HOOK = 'candidate-after-inventory-v1'
            $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory $raceOutput
            $swapOutcome = Receive-Job -Job $swapJob -Wait -ErrorAction Stop | Select-Object -Last 1
        }
        finally {
            $env:TEMP = $previousTemp
            $env:TMP = $previousTmp
            $env:KARON_EVIDENCE_INTERNAL_TEST_HOOK = $previousHook
            if ($null -ne $swapJob) {
                if ($swapJob.State -eq 'Running') { Stop-Job -Job $swapJob -ErrorAction SilentlyContinue }
                Remove-Job -Job $swapJob -Force -ErrorAction SilentlyContinue
            }
        }

        $swapOutcome | Should Match '^(fallback|hook)\|'
        $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
        $bundlePath = Join-Path $raceOutput 'test-fixture-non-runtime-component-evidence.zip'
        if (Test-Path -LiteralPath $bundlePath -PathType Leaf) {
            $archive = [System.IO.Compression.ZipFile]::OpenRead($bundlePath)
            try {
                $entry = @($archive.Entries | Where-Object { $_.FullName -ceq 'evidence/candidate-manifest.json' })[0]
                $entryStream = $entry.Open()
                $memory = New-Object System.IO.MemoryStream
                try { $entryStream.CopyTo($memory); $bundleCandidateBytes = $memory.ToArray() }
                finally { $entryStream.Dispose(); $memory.Dispose() }
            }
            finally { $archive.Dispose() }
            $bundleCandidateSha256 = Get-TestBytesSha256 $bundleCandidateBytes
            Write-Host ("RACE_RED original={0} inventory={1} zip={2} forged={3}" -f $originalCandidateSha256, $inventory.candidateManifestSha256, $bundleCandidateSha256, $forgedCandidateSha256)
            $inventory.candidateManifestSha256 | Should BeExactly $originalCandidateSha256
            $bundleCandidateSha256 | Should Not BeExactly $forgedCandidateSha256
        }

        $result.ExitCode | Should Be 1
        $blockerText = [System.IO.File]::ReadAllText((Join-Path $raceOutput 'non-runtime-component-blockers.json'))
        $blockerText | Should Match 'candidate_manifest_size_invalid'
        (Test-Path -LiteralPath $bundlePath) | Should Be $false
    }

    It 'keeps a small validated candidate immutable after its staged path is replaced' {
        $fixture = New-ComponentEvidenceFixture 'candidate-post-validation-swap'
        $raceOutput = Join-Path $fixture.Root 'output'
        $originalCandidateBytes = [System.IO.File]::ReadAllBytes($fixture.Candidate)
        $originalCandidateSha256 = Get-TestBytesSha256 $originalCandidateBytes
        $originalCandidateLength = [int64]$originalCandidateBytes.Length
        $forgedCandidateBytes = [System.Text.Encoding]::UTF8.GetBytes('{"forgedAfterValidation":true}')
        $forgedCandidatePath = Join-Path $fixture.Root 'forged-candidate-manifest.json'
        [System.IO.File]::WriteAllBytes($forgedCandidatePath, $forgedCandidateBytes)
        $forgedCandidateSha256 = Get-TestBytesSha256 $forgedCandidateBytes

        $signalPath = Join-Path $raceOutput '.candidate-after-inventory.signal'
        $continuePath = Join-Path $raceOutput '.candidate-after-inventory.continue'
        $swapJob = Start-Job -ArgumentList @($signalPath, $continuePath, $forgedCandidatePath) -ScriptBlock {
            param($SignalPath, $ContinuePath, $ForgedCandidatePath)
            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            while (-not [System.IO.File]::Exists($SignalPath)) {
                if ([DateTime]::UtcNow -ge $deadline) { throw 'internal candidate hook was not reached' }
                Start-Sleep -Milliseconds 5
            }
            $stagedCandidatePath = [System.IO.File]::ReadAllText($SignalPath).Trim()
            [System.IO.File]::WriteAllBytes($stagedCandidatePath, [System.IO.File]::ReadAllBytes($ForgedCandidatePath))
            [System.IO.File]::WriteAllText($ContinuePath, 'continue')
            "hook|$stagedCandidatePath"
        }

        $previousHook = $env:KARON_EVIDENCE_INTERNAL_TEST_HOOK
        try {
            $env:KARON_EVIDENCE_INTERNAL_TEST_HOOK = 'candidate-after-inventory-v1'
            $result = Invoke-TestCollector -Fixture $fixture -OutputDirectory $raceOutput
            $swapOutcome = Receive-Job -Job $swapJob -Wait -ErrorAction Stop | Select-Object -Last 1
        }
        finally {
            $env:KARON_EVIDENCE_INTERNAL_TEST_HOOK = $previousHook
            if ($null -ne $swapJob) {
                if ($swapJob.State -eq 'Running') { Stop-Job -Job $swapJob -ErrorAction SilentlyContinue }
                Remove-Job -Job $swapJob -Force -ErrorAction SilentlyContinue
            }
        }

        $result.ExitCode | Should Be 0
        $swapOutcome | Should Match '^hook\|'
        $inventoryPath = Join-Path $raceOutput 'source-cache-inventory.json'
        $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
        $bundlePath = Join-Path $raceOutput 'test-fixture-non-runtime-component-evidence.zip'
        $archive = [System.IO.Compression.ZipFile]::OpenRead($bundlePath)
        try {
            $entries = @($archive.Entries | Where-Object { $_.FullName -ceq 'evidence/candidate-manifest.json' })
            $entries.Count | Should Be 1
            $entryStream = $entries[0].Open()
            $memory = New-Object System.IO.MemoryStream
            try { $entryStream.CopyTo($memory); $bundleCandidateBytes = $memory.ToArray() }
            finally { $entryStream.Dispose(); $memory.Dispose() }
        }
        finally { $archive.Dispose() }

        $bundleCandidateSha256 = Get-TestBytesSha256 $bundleCandidateBytes
        $inventory.candidateManifestSha256 | Should BeExactly $originalCandidateSha256
        ([int64]$inventory.candidateManifestLength) | Should Be $originalCandidateLength
        $bundleCandidateSha256 | Should BeExactly $inventory.candidateManifestSha256
        ([int64]$bundleCandidateBytes.Length) | Should Be ([int64]$inventory.candidateManifestLength)
        $bundleCandidateSha256 | Should Not BeExactly $forgedCandidateSha256
        [System.Text.Encoding]::UTF8.GetString($bundleCandidateBytes) | Should Not Match 'forgedAfterValidation'
    }
}

function Invoke-StrictJsonInventoryZipVerifier {
    param(
        [string] $InventoryTemplate,
        [string] $ZipName,
        [string] $WorkingDirectory
    )

    $tokens = $null
    $parseErrors = $null
    $collectorAst = [Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) { throw 'collector parse failed in strict JSON fixture' }
    foreach ($functionAst in @($collectorAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst]
    }, $true))) {
        Invoke-Expression $functionAst.Extent.Text
    }

    $candidateBytes = [Text.Encoding]::UTF8.GetBytes('{}')
    $candidateSha256 = Get-TestBytesSha256 $candidateBytes
    $inventoryJson = $InventoryTemplate.Replace('__CANDIDATE_SHA256__', $candidateSha256) + "`n"
    $inventoryBytes = [Text.Encoding]::UTF8.GetBytes($inventoryJson)
    $zipPath = Join-Path $WorkingDirectory $ZipName
    New-TestZip -Path $zipPath -Entries @{
        'source-cache-inventory.json' = $inventoryBytes
        'evidence/candidate-manifest.json' = $candidateBytes
    }
    $callerExpectedEntries = @(
        [ordered]@{ name = 'source-cache-inventory.json'; expectedSha256 = Get-TestBytesSha256 $inventoryBytes; expectedLength = [long]$inventoryBytes.Length },
        [ordered]@{ name = 'evidence/candidate-manifest.json'; expectedSha256 = $candidateSha256; expectedLength = [long]$candidateBytes.Length }
    )

    try { Assert-CompletedEvidenceZip $zipPath $callerExpectedEntries }
    catch { return $_.Exception.Message }
    return $null
}

Describe 'strict JSON actual ZIP regressions' {
    $actualNonJsonZipCases = @(
        @{
            Name = 'leading-zero-length'
            Inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":02}'
        },
        @{
            Name = 'nested-object-trailing-comma'
            Inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,"nested":{"value":1,}}'
        },
        @{
            Name = 'nested-array-trailing-comma'
            Inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,"nested":[1,2,]}'
        }
    )

    It 'rejects actual ZIP non-JSON <Name>' -TestCases $actualNonJsonZipCases {
        param($Name, $Inventory)

        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $Inventory -ZipName ($Name + '.zip') -WorkingDirectory $TestDrive

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }
}

Describe 'strict JSON syntax corpus' {
    $validNumberCases = @(
        @{ Name = 'negative-zero'; Token = '-0' },
        @{ Name = 'zero'; Token = '0' },
        @{ Name = 'positive-integer'; Token = '42' },
        @{ Name = 'negative-integer'; Token = '-42' },
        @{ Name = 'positive-fraction'; Token = '0.125' },
        @{ Name = 'negative-fraction'; Token = '-12.50' },
        @{ Name = 'unsigned-exponent'; Token = '1e3' },
        @{ Name = 'signed-exponent'; Token = '-2.5E-4' }
    )

    It 'accepts strict JSON number <Name>' -TestCases $validNumberCases {
        param($Name, $Token)

        $inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,"corpusNumber":' + $Token + '}'
        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $inventory -ZipName ('valid-number-' + $Name + '.zip') -WorkingDirectory $TestDrive

        $failureToken | Should BeNullOrEmpty
    }

    $malformedNumberCases = @(
        @{ Name = 'double-zero'; Token = '00' },
        @{ Name = 'negative-leading-zero'; Token = '-01' },
        @{ Name = 'missing-integer-part'; Token = '.5' },
        @{ Name = 'missing-fraction-digits'; Token = '1.' },
        @{ Name = 'missing-exponent-digits'; Token = '1e' },
        @{ Name = 'missing-signed-exponent-digits'; Token = '1E+' },
        @{ Name = 'leading-plus'; Token = '+1' },
        @{ Name = 'double-minus'; Token = '--1' }
    )

    It 'rejects malformed JSON number <Name>' -TestCases $malformedNumberCases {
        param($Name, $Token)

        $inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,"corpusNumber":' + $Token + '}'
        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $inventory -ZipName ('invalid-number-' + $Name + '.zip') -WorkingDirectory $TestDrive

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }

    $validLiteralCases = @(
        @{ Name = 'true'; Token = 'true' },
        @{ Name = 'false'; Token = 'false' },
        @{ Name = 'null'; Token = 'null' }
    )

    It 'accepts exact JSON literal <Name>' -TestCases $validLiteralCases {
        param($Name, $Token)

        $inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,"literal":' + $Token + '}'
        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $inventory -ZipName ('valid-literal-' + $Name + '.zip') -WorkingDirectory $TestDrive

        $failureToken | Should BeNullOrEmpty
    }

    $malformedLiteralCases = @(
        @{ Name = 'capitalized-true'; Token = 'True' },
        @{ Name = 'uppercase-false'; Token = 'FALSE' },
        @{ Name = 'short-null'; Token = 'nul' },
        @{ Name = 'literal-suffix'; Token = 'nullx' }
    )

    It 'rejects malformed JSON literal <Name>' -TestCases $malformedLiteralCases {
        param($Name, $Token)

        $inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,"literal":' + $Token + '}'
        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $inventory -ZipName ('invalid-literal-' + $Name + '.zip') -WorkingDirectory $TestDrive

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }

    It 'accepts nested objects arrays strings escapes and literals' {
        $inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,"nested":{"array":[true,false,null,{"number":-0.5e+2,"text":"\"\\\/\b\f\n\r\t\u0041\uD834\uDD1E"}]}}'
        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $inventory -ZipName 'valid-nested-syntax.zip' -WorkingDirectory $TestDrive

        $failureToken | Should BeNullOrEmpty
    }

    $malformedSyntaxCases = @(
        @{ Name = 'missing-object-comma'; Tail = '"first":1 "second":2' },
        @{ Name = 'missing-array-comma'; Tail = '"nested":[1 2]' },
        @{ Name = 'invalid-simple-escape'; Tail = '"text":"\x"' },
        @{ Name = 'short-unicode-escape'; Tail = '"text":"\u12"' },
        @{ Name = 'lone-high-surrogate'; Tail = '"text":"\uD800"' },
        @{ Name = 'lone-low-surrogate'; Tail = '"text":"\uDC00"' }
    )

    It 'rejects malformed JSON syntax <Name>' -TestCases $malformedSyntaxCases {
        param($Name, $Tail)

        $inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,' + $Tail + '}'
        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $inventory -ZipName ('invalid-syntax-' + $Name + '.zip') -WorkingDirectory $TestDrive

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }

    It 'rejects extra tokens after the complete top-level value' {
        $inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2} true'
        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $inventory -ZipName 'extra-top-level-token.zip' -WorkingDirectory $TestDrive

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }

    $nestedDuplicateCases = @(
        @{
            Name = 'direct-object-escaped-alias'
            Tail = '"nested":{"name":1,"na\u006de":2}'
        },
        @{
            Name = 'object-in-array-escaped-alias'
            Tail = '"nested":[{"key":true,"k\u0065y":false}]'
        }
    )

    It 'rejects duplicate decoded nested object key <Name>' -TestCases $nestedDuplicateCases {
        param($Name, $Tail)

        $inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,' + $Tail + '}'
        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $inventory -ZipName ('nested-duplicate-' + $Name + '.zip') -WorkingDirectory $TestDrive

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }

    It 'rejects JSON nesting deeper than the 64-level safety cap' {
        $nestedValue = ('[' * 65) + '0' + (']' * 65)
        $inventory = '{"candidateManifestSha256":"__CANDIDATE_SHA256__","candidateManifestLength":2,"nested":' + $nestedValue + '}'
        $failureToken = Invoke-StrictJsonInventoryZipVerifier -InventoryTemplate $inventory -ZipName 'excessive-json-depth.zip' -WorkingDirectory $TestDrive

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }
}

Describe 'completed evidence ZIP candidate inventory cross-binding' {
    It 'rejects independently valid entries whose inventory candidate identity differs from candidate bytes' {
        $tokens = $null
        $parseErrors = $null
        $collectorAst = [Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should Be 0
        foreach ($functionAst in @($collectorAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
        }, $true))) {
            Invoke-Expression $functionAst.Extent.Text
        }

        $claimedCandidateBytes = [Text.Encoding]::UTF8.GetBytes('{"candidate":"validated"}')
        $forgedCandidateBytes = [Text.Encoding]::UTF8.GetBytes('{"candidate":"forged-after-validation"}')
        $inventoryBytes = [Text.Encoding]::UTF8.GetBytes((([ordered]@{
            candidateManifestSha256 = Get-TestBytesSha256 $claimedCandidateBytes
            candidateManifestLength = [long]$claimedCandidateBytes.Length
        } | ConvertTo-Json -Compress) + "`n"))
        $zipPath = Join-Path $TestDrive 'candidate-inventory-cross-binding.zip'
        New-TestZip -Path $zipPath -Entries @{
            'source-cache-inventory.json' = $inventoryBytes
            'evidence/candidate-manifest.json' = $forgedCandidateBytes
        }
        $callerExpectedEntries = @(
            [ordered]@{
                name = 'source-cache-inventory.json'
                expectedSha256 = Get-TestBytesSha256 $inventoryBytes
                expectedLength = [long]$inventoryBytes.Length
            },
            [ordered]@{
                name = 'evidence/candidate-manifest.json'
                expectedSha256 = Get-TestBytesSha256 $forgedCandidateBytes
                expectedLength = [long]$forgedCandidateBytes.Length
            }
        )

        $failureToken = $null
        try { Assert-CompletedEvidenceZip $zipPath $callerExpectedEntries }
        catch { $failureToken = $_.Exception.Message }

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }
    $invalidLengthCases = @(
        @{ Name = 'missing-property'; IncludeLength = $false; LengthValue = $null; CandidateLength = 0; InjectDecimal = $false },
        @{ Name = 'null'; IncludeLength = $true; LengthValue = $null; CandidateLength = 0; InjectDecimal = $false },
        @{ Name = 'string'; IncludeLength = $true; LengthValue = '2'; CandidateLength = 2; InjectDecimal = $false },
        @{ Name = 'fractional-Double'; IncludeLength = $true; LengthValue = [double]1.5; CandidateLength = 2; InjectDecimal = $false },
        @{ Name = 'fractional-Decimal'; IncludeLength = $true; LengthValue = [decimal]1.5; CandidateLength = 2; InjectDecimal = $true },
        @{ Name = 'Boolean'; IncludeLength = $true; LengthValue = $true; CandidateLength = 1; InjectDecimal = $false },
        @{ Name = 'zero'; IncludeLength = $true; LengthValue = [long]0; CandidateLength = 0; InjectDecimal = $false },
        @{ Name = 'negative'; IncludeLength = $true; LengthValue = [long]-1; CandidateLength = 0; InjectDecimal = $false },
        @{ Name = 'over-1-MiB'; IncludeLength = $true; LengthValue = [long]((1MB) + 1); CandidateLength = (1MB) + 1; InjectDecimal = $false }
    )

    It 'rejects malformed candidateManifestLength <Name>' -TestCases $invalidLengthCases {
        param($Name, $IncludeLength, $LengthValue, $CandidateLength, $InjectDecimal)

        $tokens = $null
        $parseErrors = $null
        $collectorAst = [Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should Be 0
        foreach ($functionAst in @($collectorAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
        }, $true))) {
            Invoke-Expression $functionAst.Extent.Text
        }

        $candidateBytes = New-Object byte[] ([int]$CandidateLength)
        $candidateSha256 = Get-TestBytesSha256 $candidateBytes
        $inventoryObject = [ordered]@{ candidateManifestSha256 = $candidateSha256 }
        if ($IncludeLength) { $inventoryObject.candidateManifestLength = $LengthValue }
        $inventoryBytes = [Text.Encoding]::UTF8.GetBytes((($inventoryObject | ConvertTo-Json -Compress) + "`n"))
        $zipPath = Join-Path $TestDrive ('candidate-length-' + $Name + '.zip')
        New-TestZip -Path $zipPath -Entries @{
            'source-cache-inventory.json' = $inventoryBytes
            'evidence/candidate-manifest.json' = $candidateBytes
        }
        $callerExpectedEntries = @(
            [ordered]@{ name = 'source-cache-inventory.json'; expectedSha256 = Get-TestBytesSha256 $inventoryBytes; expectedLength = [long]$inventoryBytes.Length },
            [ordered]@{ name = 'evidence/candidate-manifest.json'; expectedSha256 = $candidateSha256; expectedLength = [long]$candidateBytes.Length }
        )

        if ($InjectDecimal) {
            $decimalInventory = [pscustomobject]@{
                candidateManifestSha256 = $candidateSha256
                candidateManifestLength = [decimal]$LengthValue
            }
            function ConvertFrom-Json {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline = $true)] $InputObject)
                process { $decimalInventory }
            }
        }
        $failureToken = $null
        try { Assert-CompletedEvidenceZip $zipPath $callerExpectedEntries }
        catch { $failureToken = $_.Exception.Message }
        finally {
            if ($InjectDecimal) { Remove-Item -LiteralPath Function:\ConvertFrom-Json -ErrorAction SilentlyContinue }
        }

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }

    $invalidShaCases = @(
        @{ Name = 'missing-property'; IncludeSha = $false; ShaValue = $null },
        @{ Name = 'null'; IncludeSha = $true; ShaValue = $null },
        @{ Name = 'single-element-array'; IncludeSha = $true; ShaValue = 'VALID_SHA_ARRAY' },
        @{ Name = 'Int64'; IncludeSha = $true; ShaValue = [long]123 },
        @{ Name = 'Boolean'; IncludeSha = $true; ShaValue = $true },
        @{ Name = 'short-string'; IncludeSha = $true; ShaValue = ('a' * 63) },
        @{ Name = 'non-hex-string'; IncludeSha = $true; ShaValue = ('g' * 64) },
        @{ Name = 'wrong-length-string'; IncludeSha = $true; ShaValue = ('a' * 65) }
    )

    It 'rejects malformed candidateManifestSha256 <Name>' -TestCases $invalidShaCases {
        param($Name, $IncludeSha, $ShaValue)

        $tokens = $null
        $parseErrors = $null
        $collectorAst = [Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should Be 0
        foreach ($functionAst in @($collectorAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
        }, $true))) {
            Invoke-Expression $functionAst.Extent.Text
        }

        $candidateBytes = [Text.Encoding]::UTF8.GetBytes('{}')
        $candidateSha256 = Get-TestBytesSha256 $candidateBytes
        if ($ShaValue -is [string] -and $ShaValue -ceq 'VALID_SHA_ARRAY') { $ShaValue = @($candidateSha256.ToLowerInvariant()) }
        $inventoryObject = [ordered]@{ candidateManifestLength = [long]$candidateBytes.Length }
        if ($IncludeSha) { $inventoryObject.candidateManifestSha256 = $ShaValue }
        $inventoryBytes = [Text.Encoding]::UTF8.GetBytes((($inventoryObject | ConvertTo-Json -Compress) + "`n"))
        $zipPath = Join-Path $TestDrive ('candidate-sha-' + $Name + '.zip')
        New-TestZip -Path $zipPath -Entries @{
            'source-cache-inventory.json' = $inventoryBytes
            'evidence/candidate-manifest.json' = $candidateBytes
        }
        $callerExpectedEntries = @(
            [ordered]@{ name = 'source-cache-inventory.json'; expectedSha256 = Get-TestBytesSha256 $inventoryBytes; expectedLength = [long]$inventoryBytes.Length },
            [ordered]@{ name = 'evidence/candidate-manifest.json'; expectedSha256 = $candidateSha256; expectedLength = [long]$candidateBytes.Length }
        )

        $failureToken = $null
        try { Assert-CompletedEvidenceZip $zipPath $callerExpectedEntries }
        catch { $failureToken = $_.Exception.Message }

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }

    It 'accepts the exact 1 MiB candidateManifestLength boundary' {
        $tokens = $null
        $parseErrors = $null
        $collectorAst = [Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should Be 0
        foreach ($functionAst in @($collectorAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
        }, $true))) {
            Invoke-Expression $functionAst.Extent.Text
        }

        $candidateBytes = New-Object byte[] (1MB)
        $candidateSha256 = Get-TestBytesSha256 $candidateBytes
        $inventoryBytes = [Text.Encoding]::UTF8.GetBytes((([ordered]@{
            candidateManifestSha256 = $candidateSha256
            candidateManifestLength = [long]$candidateBytes.Length
        } | ConvertTo-Json -Compress) + "`n"))
        $zipPath = Join-Path $TestDrive 'candidate-exact-1mib.zip'
        New-TestZip -Path $zipPath -Entries @{
            'source-cache-inventory.json' = $inventoryBytes
            'evidence/candidate-manifest.json' = $candidateBytes
        }
        $callerExpectedEntries = @(
            [ordered]@{ name = 'source-cache-inventory.json'; expectedSha256 = Get-TestBytesSha256 $inventoryBytes; expectedLength = [long]$inventoryBytes.Length },
            [ordered]@{ name = 'evidence/candidate-manifest.json'; expectedSha256 = $candidateSha256; expectedLength = [long]$candidateBytes.Length }
        )

        $failureToken = $null
        try { Assert-CompletedEvidenceZip $zipPath $callerExpectedEntries }
        catch { $failureToken = $_.Exception.Message }

        $failureToken | Should BeNullOrEmpty
    }

    It 'rejects a trailing comma after the candidate identity fields' {
        $tokens = $null
        $parseErrors = $null
        $collectorAst = [Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should Be 0
        foreach ($functionAst in @($collectorAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
        }, $true))) {
            Invoke-Expression $functionAst.Extent.Text
        }

        $candidateBytes = [Text.Encoding]::UTF8.GetBytes('{}')
        $candidateSha256 = Get-TestBytesSha256 $candidateBytes
        $inventoryJson = '{"candidateManifestSha256":"' + $candidateSha256 + '","candidateManifestLength":2,}' + "`n"
        $inventoryBytes = [Text.Encoding]::UTF8.GetBytes($inventoryJson)
        $zipPath = Join-Path $TestDrive 'candidate-trailing-comma.zip'
        New-TestZip -Path $zipPath -Entries @{
            'source-cache-inventory.json' = $inventoryBytes
            'evidence/candidate-manifest.json' = $candidateBytes
        }
        $callerExpectedEntries = @(
            [ordered]@{ name = 'source-cache-inventory.json'; expectedSha256 = Get-TestBytesSha256 $inventoryBytes; expectedLength = [long]$inventoryBytes.Length },
            [ordered]@{ name = 'evidence/candidate-manifest.json'; expectedSha256 = $candidateSha256; expectedLength = [long]$candidateBytes.Length }
        )

        $failureToken = $null
        try { Assert-CompletedEvidenceZip $zipPath $callerExpectedEntries }
        catch { $failureToken = $_.Exception.Message }

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }

    It 'accepts a lowercase 64-hex SHA string after normalization' {
        $tokens = $null
        $parseErrors = $null
        $collectorAst = [Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should Be 0
        foreach ($functionAst in @($collectorAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
        }, $true))) {
            Invoke-Expression $functionAst.Extent.Text
        }

        $candidateBytes = [Text.Encoding]::UTF8.GetBytes('{"candidate":"lowercase-sha"}')
        $candidateSha256 = Get-TestBytesSha256 $candidateBytes
        $inventoryBytes = [Text.Encoding]::UTF8.GetBytes((([ordered]@{
            candidateManifestSha256 = $candidateSha256.ToLowerInvariant()
            candidateManifestLength = [long]$candidateBytes.Length
        } | ConvertTo-Json -Compress) + "`n"))
        $zipPath = Join-Path $TestDrive 'candidate-lowercase-sha.zip'
        New-TestZip -Path $zipPath -Entries @{
            'source-cache-inventory.json' = $inventoryBytes
            'evidence/candidate-manifest.json' = $candidateBytes
        }
        $callerExpectedEntries = @(
            [ordered]@{ name = 'source-cache-inventory.json'; expectedSha256 = Get-TestBytesSha256 $inventoryBytes; expectedLength = [long]$inventoryBytes.Length },
            [ordered]@{ name = 'evidence/candidate-manifest.json'; expectedSha256 = $candidateSha256; expectedLength = [long]$candidateBytes.Length }
        )

        $failureToken = $null
        try { Assert-CompletedEvidenceZip $zipPath $callerExpectedEntries }
        catch { $failureToken = $_.Exception.Message }

        $failureToken | Should BeNullOrEmpty
    }

    $duplicateIdentityCases = @(
        @{ Identity = 'SHA'; Spelling = 'exact'; Order = 'invalid-first-valid-last' },
        @{ Identity = 'SHA'; Spelling = 'exact'; Order = 'valid-first-invalid-last' },
        @{ Identity = 'SHA'; Spelling = 'escaped-alias'; Order = 'invalid-first-valid-last' },
        @{ Identity = 'SHA'; Spelling = 'escaped-alias'; Order = 'valid-first-invalid-last' },
        @{ Identity = 'length'; Spelling = 'exact'; Order = 'invalid-first-valid-last' },
        @{ Identity = 'length'; Spelling = 'exact'; Order = 'valid-first-invalid-last' },
        @{ Identity = 'length'; Spelling = 'escaped-alias'; Order = 'invalid-first-valid-last' },
        @{ Identity = 'length'; Spelling = 'escaped-alias'; Order = 'valid-first-invalid-last' }
    )

    It 'rejects duplicate candidate identity <Identity> <Spelling> <Order>' -TestCases $duplicateIdentityCases {
        param($Identity, $Spelling, $Order)

        $tokens = $null
        $parseErrors = $null
        $collectorAst = [Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should Be 0
        foreach ($functionAst in @($collectorAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
        }, $true))) {
            Invoke-Expression $functionAst.Extent.Text
        }

        $candidateBytes = [Text.Encoding]::UTF8.GetBytes('{}')
        $candidateSha256 = Get-TestBytesSha256 $candidateBytes
        if ($Identity -ceq 'SHA') {
            $exactKey = 'candidateManifestSha256'
            $escapedKey = 'candidateManifestSha\u0032\u0035\u0036'
            $singlePair = '"candidateManifestLength":2'
            $invalidValue = 'null'
            $validValue = '"' + $candidateSha256.ToLowerInvariant() + '"'
        }
        else {
            $exactKey = 'candidateManifestLength'
            $escapedKey = 'candidateManifest\u004cength'
            $singlePair = '"candidateManifestSha256":"' + $candidateSha256 + '"'
            $invalidValue = '"2"'
            $validValue = '2'
        }
        if ($Spelling -ceq 'exact') {
            $firstKey = $exactKey
            $secondKey = $exactKey
        }
        elseif ($Order -ceq 'invalid-first-valid-last') {
            $firstKey = $exactKey
            $secondKey = $escapedKey
        }
        else {
            $firstKey = $escapedKey
            $secondKey = $exactKey
        }
        if ($Order -ceq 'invalid-first-valid-last') {
            $firstValue = $invalidValue
            $secondValue = $validValue
        }
        else {
            $firstValue = $validValue
            $secondValue = $invalidValue
        }
        $inventoryJson = '{' + $singlePair + ',"' + $firstKey + '":' + $firstValue + ',"' + $secondKey + '":' + $secondValue + "}`n"
        $inventoryBytes = [Text.Encoding]::UTF8.GetBytes($inventoryJson)
        $zipPath = Join-Path $TestDrive ('candidate-duplicate-' + $Identity + '-' + $Spelling + '-' + $Order + '.zip')
        New-TestZip -Path $zipPath -Entries @{
            'source-cache-inventory.json' = $inventoryBytes
            'evidence/candidate-manifest.json' = $candidateBytes
        }
        $callerExpectedEntries = @(
            [ordered]@{ name = 'source-cache-inventory.json'; expectedSha256 = Get-TestBytesSha256 $inventoryBytes; expectedLength = [long]$inventoryBytes.Length },
            [ordered]@{ name = 'evidence/candidate-manifest.json'; expectedSha256 = $candidateSha256; expectedLength = [long]$candidateBytes.Length }
        )

        $failureToken = $null
        try { Assert-CompletedEvidenceZip $zipPath $callerExpectedEntries }
        catch { $failureToken = $_.Exception.Message }

        $failureToken | Should Be 'bundle_candidate_inventory_mismatch'
    }
}
