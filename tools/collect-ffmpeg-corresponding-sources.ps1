[CmdletBinding()]
param(
    [string] $ManifestPath,
    [string] $BinaryArchivePath = 'E:\03_AllWork\ytdlp-korean-interface\.quality-presets-work\karon2-input\immutable\ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip',
    [string] $ScratchRoot = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-6-ffmpeg-corresponding-sources',
    [string] $CacheRoot,
    [switch] $NoExecute
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $PSScriptRoot '..\release\runtime\v2.19.1-karon.2\ffmpeg\manifest.json'
}

function Get-UpperSha256 {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-SourceArchiveHash {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $ExpectedSha256,
        [Parameter(Mandatory)][string] $ComponentId
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "ffmpeg_source_missing_archive:$ComponentId"
    }
    if ((Get-UpperSha256 -Path $Path) -cne $ExpectedSha256.ToUpperInvariant()) {
        throw "ffmpeg_source_sha256_mismatch:$ComponentId"
    }
}

function Test-ImmutableSourceUrl {
    param([Parameter(Mandatory)][string] $Url)
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref] $uri)) { return $false }
    if ($uri.Scheme -cne 'https' -or -not [string]::IsNullOrEmpty($uri.Query)) { return $false }
    if ($uri.AbsolutePath -match '/actions/artifacts/[0-9]+/zip$') { return $true }
    return $uri.AbsolutePath -match '(?i)(^|[/._-])[0-9a-f]{40}([/._-]|$)'
}

function Test-ExternalBuildOption {
    param([Parameter(Mandatory)][string] $Option)
    if ($Option -match '^--enable-lib[a-z0-9-]+$') { return $true }
    return $Option -match '^--enable-(zlib|iconv|gmp|lzma|fontconfig|vulkan|opencl|amf|chromaprint|ffnvcodec|openal|sdl2|vaapi)$'
}

function Assert-FfmpegSourceManifest {
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)][string[]] $BuildConfigurationOptions
    )

    foreach ($forbidden in @('--enable-gpl', '--enable-nonfree')) {
        if ($BuildConfigurationOptions -ccontains $forbidden) {
            throw "ffmpeg_source_forbidden_configuration:$forbidden"
        }
    }
    foreach ($required in @('--pkg-config-flags=--static', '--enable-version3')) {
        if ($BuildConfigurationOptions -cnotcontains $required) {
            throw "ffmpeg_source_configuration_mismatch:$required"
        }
    }

    $included = @{}
    foreach ($path in @($Manifest.includedPaths)) {
        $key = ([string] $path).ToLowerInvariant()
        if ($included.ContainsKey($key)) { throw "ffmpeg_source_duplicate_path:$path" }
        $included[$key] = $true
    }

    $components = @{}
    foreach ($component in @($Manifest.components)) {
        $id = [string] $component.id
        $key = $id.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($id)) { throw 'ffmpeg_source_component_missing_id' }
        if ($components.ContainsKey($key)) { throw "ffmpeg_source_duplicate_component:$id" }
        $components[$key] = $component

        if (-not (Test-ImmutableSourceUrl -Url ([string] $component.source.url))) {
            throw "ffmpeg_source_mutable_url:$id"
        }
        if ([string] $component.source.sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "ffmpeg_source_missing_sha256:$id"
        }
        if ([string]::IsNullOrWhiteSpace([string] $component.license.expression) -or
            [string]::IsNullOrWhiteSpace([string] $component.license.textPath) -or
            -not $included.ContainsKey(([string] $component.license.textPath).ToLowerInvariant())) {
            throw "ffmpeg_source_missing_license:$id"
        }
        if ([string]::IsNullOrWhiteSpace([string] $component.recipe.scriptPath) -or
            -not $included.ContainsKey(([string] $component.recipe.scriptPath).ToLowerInvariant())) {
            throw "ffmpeg_source_missing_recipe:$id"
        }
        foreach ($patch in @($component.recipe.patches)) {
            if (-not $included.ContainsKey(([string] $patch).ToLowerInvariant())) {
                throw "ffmpeg_source_missing_patch:${id}:$patch"
            }
        }
    }

    $mappedOptions = @{}
    foreach ($mapping in @($Manifest.enabledExternalLibraries)) {
        $option = [string] $mapping.option
        if ($mappedOptions.ContainsKey($option)) { throw "ffmpeg_source_duplicate_option:$option" }
        $componentKey = ([string] $mapping.componentId).ToLowerInvariant()
        if (-not $components.ContainsKey($componentKey)) { throw "ffmpeg_source_unknown_component:$option" }
        $mappedOptions[$option] = $componentKey
    }
    foreach ($option in $BuildConfigurationOptions) {
        if ((Test-ExternalBuildOption -Option $option) -and -not $mappedOptions.ContainsKey($option)) {
            throw "ffmpeg_source_unknown_enabled_library:$option"
        }
    }
    foreach ($option in $mappedOptions.Keys) {
        if ($BuildConfigurationOptions -cnotcontains $option) {
            throw "ffmpeg_source_configuration_mismatch:$option"
        }
    }
    if ([string] $Manifest.closureStatus -cne 'complete') {
        throw 'ffmpeg_source_closure_incomplete'
    }
}

function Read-FfmpegBinaryEvidence {
    param(
        [Parameter(Mandatory)][string] $ArchivePath,
        [Parameter(Mandatory)][string] $ExpectedArchiveSha256,
        [Parameter(Mandatory)][string] $ExpectedFfmpegSha256,
        [Parameter(Mandatory)][string] $ExpectedFfprobeSha256,
        [Parameter(Mandatory)][string] $ExpectedVersion
    )

    Assert-SourceArchiveHash -Path $ArchivePath -ExpectedSha256 $ExpectedArchiveSha256 -ComponentId 'binary-archive'
    $extractionRoot = Join-Path ([IO.Path]::GetTempPath()) ('karon-ffmpeg-buildconf-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($extractionRoot) | Out-Null
    try {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $extractionRoot
        $ffmpegFiles = @(Get-ChildItem -LiteralPath $extractionRoot -Filter 'ffmpeg.exe' -File -Recurse)
        $ffprobeFiles = @(Get-ChildItem -LiteralPath $extractionRoot -Filter 'ffprobe.exe' -File -Recurse)
        if ($ffmpegFiles.Count -cne 1 -or $ffprobeFiles.Count -cne 1) { throw 'ffmpeg_source_binary_layout_mismatch' }
        $ffmpegSha = Get-UpperSha256 -Path $ffmpegFiles[0].FullName
        $ffprobeSha = Get-UpperSha256 -Path $ffprobeFiles[0].FullName
        if ($ffmpegSha -cne $ExpectedFfmpegSha256.ToUpperInvariant()) { throw 'ffmpeg_source_binary_sha256_mismatch:ffmpeg' }
        if ($ffprobeSha -cne $ExpectedFfprobeSha256.ToUpperInvariant()) { throw 'ffmpeg_source_binary_sha256_mismatch:ffprobe' }

        $buildconf = @(& $ffmpegFiles[0].FullName -hide_banner -buildconf 2>&1 | ForEach-Object { $_.ToString() })
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg_source_buildconf_failed:$LASTEXITCODE" }
        $versionOutput = @(& $ffmpegFiles[0].FullName -hide_banner -version 2>&1 | ForEach-Object { $_.ToString() })
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg_source_version_failed:$LASTEXITCODE" }
        if ($versionOutput.Count -eq 0 -or $versionOutput[0] -notmatch ('^ffmpeg version ' + [regex]::Escape($ExpectedVersion) + '([-\s]|$)')) {
            throw 'ffmpeg_source_binary_version_mismatch'
        }
        $options = @($buildconf | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^--' })
        return [pscustomobject][ordered]@{
            archiveSha256 = (Get-UpperSha256 -Path $ArchivePath)
            ffmpegSha256 = $ffmpegSha
            ffprobeSha256 = $ffprobeSha
            versionLine = $versionOutput[0]
            configurationOptions = $options
            rawBuildConfiguration = ($buildconf -join "`n")
        }
    }
    finally {
        Remove-Item -LiteralPath $extractionRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-VerifiedSourceArchive {
    param(
        [Parameter(Mandatory)] $Component,
        [Parameter(Mandatory)][string] $DestinationRoot
    )
    $sha = ([string] $Component.source.sha256).ToUpperInvariant()
    $directory = Join-Path (Join-Path $DestinationRoot 'sha256') $sha.Substring(0, 2)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $destination = Join-Path $directory $sha
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        if (-not (Test-ImmutableSourceUrl -Url ([string] $Component.source.url))) {
            throw "ffmpeg_source_mutable_url:$($Component.id)"
        }
        $temporary = $destination + '.partial.' + [Guid]::NewGuid().ToString('N')
        try {
            Invoke-WebRequest -UseBasicParsing -Uri ([string] $Component.source.url) -OutFile $temporary
            Assert-SourceArchiveHash -Path $temporary -ExpectedSha256 $sha -ComponentId ([string] $Component.id)
            Move-Item -LiteralPath $temporary -Destination $destination
        }
        finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
    Assert-SourceArchiveHash -Path $destination -ExpectedSha256 $sha -ComponentId ([string] $Component.id)
    return [pscustomobject][ordered]@{ id = [string] $Component.id; sha256 = $sha; path = $destination }
}

function New-DeterministicZip {
    param([Parameter(Mandatory)][object[]] $Items, [Parameter(Mandatory)][string] $OutputPath)
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($item in @($Items | Sort-Object EntryPath)) {
                $entry = $archive.CreateEntry(([string] $item.EntryPath).Replace('\', '/'), [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $input = [IO.File]::OpenRead([string] $item.SourcePath)
                $output = $entry.Open()
                try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Invoke-FfmpegSourceCollector {
    param(
        [Parameter(Mandatory)][string] $InputManifestPath,
        [Parameter(Mandatory)][string] $InputBinaryArchivePath,
        [Parameter(Mandatory)][string] $OutputRoot,
        [Parameter(Mandatory)][string] $ContentCacheRoot
    )
    $manifest = Get-Content -LiteralPath $InputManifestPath -Raw | ConvertFrom-Json
    if ([int] $manifest.schemaVersion -cne 1) { throw 'ffmpeg_source_manifest_schema_unsupported' }
    [IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
    [IO.Directory]::CreateDirectory($ContentCacheRoot) | Out-Null

    $evidence = Read-FfmpegBinaryEvidence `
        -ArchivePath $InputBinaryArchivePath `
        -ExpectedArchiveSha256 ([string] $manifest.binary.archiveSha256) `
        -ExpectedFfmpegSha256 ([string] $manifest.binary.ffmpegSha256) `
        -ExpectedFfprobeSha256 ([string] $manifest.binary.ffprobeSha256) `
        -ExpectedVersion ([string] $manifest.binary.expectedVersion)

    $manifestRoot = Split-Path -Parent (Resolve-Path -LiteralPath $InputManifestPath)
    $expectedOptions = @(Get-Content -LiteralPath (Join-Path $manifestRoot ([string] $manifest.binary.buildConfigurationPath)) |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^--' })
    if (($expectedOptions -join "`n") -cne (@($evidence.configurationOptions) -join "`n")) {
        throw 'ffmpeg_source_build_configuration_mismatch'
    }
    foreach ($forbidden in @('--enable-gpl', '--enable-nonfree')) {
        if (@($evidence.configurationOptions) -ccontains $forbidden) { throw "ffmpeg_source_forbidden_configuration:$forbidden" }
    }

    $binaryEvidencePath = Join-Path $OutputRoot 'binary-evidence.json'
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $binaryEvidencePath -Encoding UTF8
    $cachedSources = @($manifest.components | ForEach-Object {
        Get-VerifiedSourceArchive -Component $_ -DestinationRoot $ContentCacheRoot
    })

    if ([string] $manifest.closureStatus -cne 'complete') {
        $result = [pscustomobject][ordered]@{
            status = 'blocked'
            reason = 'ffmpeg_source_closure_incomplete'
            binaryEvidencePath = $binaryEvidencePath
            cachedSources = $cachedSources
            unresolvedItems = @($manifest.unresolvedItems)
        }
        $resultPath = Join-Path $OutputRoot 'collector-result.json'
        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        throw 'ffmpeg_source_closure_incomplete'
    }

    Assert-FfmpegSourceManifest -Manifest $manifest -BuildConfigurationOptions @($evidence.configurationOptions)
    $inventory = @($cachedSources | Sort-Object id | ForEach-Object {
        [pscustomobject][ordered]@{ componentId = $_.id; sha256 = $_.sha256; bundlePath = "sources/$($_.id).source" }
    })
    $inventoryPath = Join-Path $OutputRoot 'inventory.json'
    $inventory | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $inventoryPath -Encoding UTF8
    $items = @($cachedSources | ForEach-Object {
        [pscustomobject]@{ SourcePath = $_.path; EntryPath = "sources/$($_.id).source" }
    })
    $items += [pscustomobject]@{ SourcePath = $InputManifestPath; EntryPath = 'manifest.json' }
    $items += [pscustomobject]@{ SourcePath = $inventoryPath; EntryPath = 'inventory.json' }
    foreach ($relativePath in @($manifest.includedPaths)) {
        $items += [pscustomobject]@{ SourcePath = (Join-Path $manifestRoot ([string] $relativePath)); EntryPath = [string] $relativePath }
    }
    $bundlePath = Join-Path $OutputRoot 'ytdlp-korean-interface-v2.19.1-karon.2-ffmpeg-corresponding-sources.zip'
    New-DeterministicZip -Items $items -OutputPath $bundlePath
    return [pscustomobject][ordered]@{
        status = 'complete'
        sourceCount = $cachedSources.Count
        bundlePath = $bundlePath
        bundleSha256 = (Get-UpperSha256 -Path $bundlePath)
        inventoryPath = $inventoryPath
    }
}

if (-not $NoExecute) {
    if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $ScratchRoot 'cache' }
    Invoke-FfmpegSourceCollector -InputManifestPath $ManifestPath -InputBinaryArchivePath $BinaryArchivePath -OutputRoot $ScratchRoot -ContentCacheRoot $CacheRoot
}
