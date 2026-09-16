[CmdletBinding()]
param(
    [string] $ManifestPath,
    [string] $BinaryArchivePath = 'E:\03_AllWork\ytdlp-korean-interface\.quality-presets-work\karon2-input\immutable\ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip',
    [string] $ScratchRoot = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-6-ffmpeg-corresponding-sources',
    [string] $CacheRoot,
    [string] $BtbNCacheRoot = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-6-actions-download-cache\extracted',
    [string] $Rav1eCrateCacheRoot = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-6-rav1e-crates',
    [string] $ToolchainSourceRoot = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-6-toolchain-sources',
    [switch] $NoExecute
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $PSScriptRoot '..\release\runtime\v2.19.1-karon.2\ffmpeg\manifest.json'
}

function Get-UpperSha256 {
    param([string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-SourceArchiveHash {
    param([string] $Path, [string] $ExpectedSha256, [string] $ComponentId)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "ffmpeg_source_missing_archive:$ComponentId" }
    if ((Get-UpperSha256 $Path) -cne $ExpectedSha256.ToUpperInvariant()) { throw "ffmpeg_source_sha256_mismatch:$ComponentId" }
}

function Test-ImmutableSourceUrl {
    param([string] $Url)
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref] $uri)) { return $false }
    if ($uri.Scheme -cne 'https' -or -not [string]::IsNullOrEmpty($uri.Query)) { return $false }
    if ($uri.AbsolutePath -match '(?i)/(main|master|latest|head)([/._-]|$)') { return $false }
    if ($uri.AbsolutePath -match '/actions/artifacts/[0-9]+/zip$') { return $true }
    if ($uri.Host -ceq 'static.crates.io' -and $uri.AbsolutePath -match '^/crates/[^/]+/[^/]+-[0-9][^/]*\.crate$') { return $true }
    if ($uri.AbsolutePath -match '(?i)(^|[/._-])[0-9a-f]{40}([/._-]|$)') { return $true }
    $uri.AbsolutePath -match '(?i)(^|/)(v?[0-9]+(?:\.[0-9]+){1,3}[^/]*)[/._-]|[-_]v?[0-9]+(?:\.[0-9]+){1,3}[^/]*\.(tar\.(xz|bz2|gz)|zip)$'
}

function Test-ExternalBuildOption {
    param([string] $Option)
    if ($Option -match '^--enable-lib[a-z0-9-]+$') { return $true }
    $Option -match '^--enable-(zlib|iconv|gmp|lzma|fontconfig|vulkan|opencl|amf|chromaprint|ffnvcodec|openal|sdl2|vaapi|lv2)$'
}

function Assert-SafeBundlePath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.IndexOf([char] 0) -ge 0 -or
        [IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:' -or
        $Path -match '^[\\/]{2}' -or $Path.Contains(':')) {
        throw "ffmpeg_source_unsafe_bundle_path:$Path"
    }
    $normalized = $Path.Replace('\', '/')
    $segments = $normalized.Split([char] '/', [StringSplitOptions]::None)
    foreach ($segment in $segments) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -ceq '.' -or $segment -ceq '..' -or
            $segment -match '[ .]$' -or $segment.IndexOfAny([char[]] '<>"|?*') -ge 0 -or
            $segment -match '(?i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw "ffmpeg_source_unsafe_bundle_path:$Path"
        }
    }
    $normalized.Normalize([Text.NormalizationForm]::FormC)
}

function Resolve-ContainedSourcePath {
    param([string] $SourcePath, [string[]] $AllowedSourceRoots)
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "ffmpeg_source_missing_bundle_input:$SourcePath" }
    $item = Get-Item -LiteralPath $SourcePath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "ffmpeg_source_source_root_escape:$SourcePath" }
    $resolved = [IO.Path]::GetFullPath($item.FullName)
    foreach ($root in $AllowedSourceRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $rootPath = [IO.Path]::GetFullPath((Get-Item -LiteralPath $root -Force).FullName).TrimEnd('\', '/')
        $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
        if ($resolved.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
            $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $resolved
        }
    }
    throw "ffmpeg_source_source_root_escape:$SourcePath"
}

function Assert-BundleItems {
    param([object[]] $Items, [string[]] $AllowedSourceRoots)
    $seen = @{}
    foreach ($item in $Items) {
        $entryPath = Assert-SafeBundlePath ([string] $item.EntryPath)
        $key = $entryPath.Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "ffmpeg_source_duplicate_path:$entryPath" }
        $seen[$key] = $true
        $sourcePath = Resolve-ContainedSourcePath ([string] $item.SourcePath) $AllowedSourceRoots
        $sha = ([string] $item.Sha256).ToUpperInvariant()
        if ($sha -notmatch '^[0-9A-F]{64}$') { throw "ffmpeg_source_missing_sha256:$entryPath" }
        [pscustomobject][ordered]@{
            SourcePath = $sourcePath
            EntryPath = $entryPath
            Sha256 = $sha
            Bytes = [int64] $item.Bytes
        }
    }
}

function Get-GitBlobBytes {
    param([string] $RepositoryRoot, [string] $ObjectSpec)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'git'
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-C', $RepositoryRoot, 'cat-file', 'blob', $ObjectSpec)) { [void] $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void] $process.Start()
    $buffer = [IO.MemoryStream]::new()
    try {
        $process.StandardOutput.BaseStream.CopyTo($buffer)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "ffmpeg_source_git_license_blob_missing:$ObjectSpec`n$errorText" }
        return ,$buffer.ToArray()
    }
    finally {
        $buffer.Dispose()
        $process.Dispose()
    }
}

function Assert-GitLicenseCorpus {
    param($Corpus, [string] $ManifestRoot, [string] $Revision = 'HEAD')
    $repositoryRoot = @(& git -C $ManifestRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $repositoryRoot.Count -ne 1) { throw 'ffmpeg_source_git_repository_unavailable' }
    $repositoryRoot = $repositoryRoot[0].Trim()
    $relativeManifestRoot = [IO.Path]::GetRelativePath($repositoryRoot, [IO.Path]::GetFullPath($ManifestRoot)).Replace('\', '/')
    if ($relativeManifestRoot -eq '..' -or $relativeManifestRoot.StartsWith('../', [StringComparison]::Ordinal)) {
        throw 'ffmpeg_source_git_repository_unavailable'
    }
    $trackedRoot = "$relativeManifestRoot/licenses/extracted"
    $tracked = @(& git -C $repositoryRoot ls-tree -r --name-only $Revision -- $trackedRoot)
    if ($LASTEXITCODE -ne 0) { throw 'ffmpeg_source_git_license_tree_unavailable' }
    $trackedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $tracked) { [void] $trackedSet.Add($path) }
    if ($trackedSet.Count -ne [int] $Corpus.textObjectCount) { throw 'ffmpeg_source_git_license_tree_count_mismatch' }
    foreach ($text in @($Corpus.textObjects)) {
        $bundlePath = Assert-SafeBundlePath ([string] $text.bundlePath)
        if (-not $bundlePath.StartsWith('licenses/extracted/', [StringComparison]::Ordinal)) {
            throw "ffmpeg_source_invalid_license_path:$bundlePath"
        }
        $repositoryPath = "$relativeManifestRoot/$bundlePath"
        if (-not $trackedSet.Contains($repositoryPath)) { throw "ffmpeg_source_git_license_blob_missing:$repositoryPath" }
        $bytes = Get-GitBlobBytes $repositoryRoot "${Revision}:$repositoryPath"
        $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        if ($sha -cne ([string] $text.sha256).ToUpperInvariant() -or $bytes.Length -ne [int64] $text.bytes) {
            throw "ffmpeg_source_git_license_blob_mismatch:$repositoryPath"
        }
    }
    [pscustomobject][ordered]@{ revision = $Revision; verifiedBlobCount = $trackedSet.Count }
}

function Assert-LicenseCorpus {
    param($Corpus, [string] $ManifestRoot, [switch] $VerifyFiles)
    $refs = @{}
    foreach ($text in @($Corpus.textObjects)) {
        $sha = ([string] $text.sha256).ToUpperInvariant()
        $ref = [string] $text.licenseRef
        if ($sha -notmatch '^[0-9A-F]{64}$' -or $ref -cne ('LicenseRef-' + $sha.Substring(0, 16).ToLowerInvariant())) {
            throw 'ffmpeg_source_invalid_license_ref'
        }
        if ($refs.ContainsKey($sha)) { throw "ffmpeg_source_duplicate_license_text:$sha" }
        $refs[$sha] = $ref
        if ($VerifyFiles) {
            $path = Join-Path $ManifestRoot (Assert-SafeBundlePath ([string] $text.bundlePath))
            Assert-SourceArchiveHash $path $sha $ref
            if ((Get-Item -LiteralPath $path).Length -ne [int64] $text.bytes) { throw "ffmpeg_source_license_length_mismatch:$ref" }
        }
    }
    if ($refs.Count -cne [int] $Corpus.textObjectCount) { throw 'ffmpeg_source_license_corpus_count_mismatch' }
    $refs
}

function Assert-LicenseRecord {
    param($License, [string] $Id, [hashtable] $Refs)
    $expression = [string] $License.expression
    if ([string]::IsNullOrWhiteSpace($expression) -or $expression -match 'NOASSERTION' -or @($License.files).Count -eq 0) {
        throw "ffmpeg_source_missing_license:$Id"
    }
    foreach ($file in @($License.files)) {
        $sha = ([string] $file.sha256).ToUpperInvariant()
        $ref = [string] $file.licenseRef
        if (-not $Refs.ContainsKey($sha) -or $Refs[$sha] -cne $ref -or $expression -notmatch [regex]::Escape($ref)) {
            throw "ffmpeg_source_missing_license:$Id"
        }
    }
}

function Assert-FfmpegClosureMetadata {
    param($Manifest, $Graph, $Crates, $Toolchain, $Corpus, [string[]] $Options)
    foreach ($forbidden in @('--enable-gpl', '--enable-nonfree')) {
        if ($Options -ccontains $forbidden) { throw "ffmpeg_source_forbidden_configuration:$forbidden" }
    }
    foreach ($required in @('--pkg-config-flags=--static', '--enable-version3')) {
        if ($Options -cnotcontains $required) { throw "ffmpeg_source_configuration_mismatch:$required" }
    }
    if ([string] $Manifest.closureStatus -cne 'complete' -or @($Manifest.unresolvedItems).Count -ne 0) { throw 'ffmpeg_source_closure_incomplete' }

    $included = @{}
    foreach ($path in @($Manifest.includedPaths)) {
        $key = ([string] $path).ToLowerInvariant()
        if ($included.ContainsKey($key)) { throw "ffmpeg_source_duplicate_path:$path" }
        $included[$key] = $true
    }
    foreach ($name in @('ffmpeg', 'btbnScripts', 'spdxLicenseList')) {
        $source = $Manifest.sourceSets.$name
        if (-not (Test-ImmutableSourceUrl ([string] $source.url))) { throw "ffmpeg_source_mutable_url:$name" }
        if ([string] $source.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "ffmpeg_source_missing_sha256:$name" }
        if ([string]::IsNullOrWhiteSpace([string] $source.licenseExpression) -or [string] $source.licenseExpression -match 'NOASSERTION') {
            throw "ffmpeg_source_missing_license:$name"
        }
    }

    $refs = Assert-LicenseCorpus $Corpus ''
    $components = @{}
    foreach ($component in @($Graph.components)) {
        $id = [string] $component.id
        $key = $id.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($id) -or $components.ContainsKey($key)) { throw "ffmpeg_source_duplicate_component:$id" }
        $components[$key] = $true
        if ([string] $component.applicability -cne 'conservative-superset') { throw "ffmpeg_source_invalid_applicability:$id" }
        if (-not (Test-ImmutableSourceUrl ([string] $component.source.url))) { throw "ffmpeg_source_mutable_url:$id" }
        if ([string] $component.source.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "ffmpeg_source_missing_sha256:$id" }
        Assert-LicenseRecord $component.license $id $refs
        if ([string]::IsNullOrWhiteSpace([string] $component.recipe.scriptPath) -or [string] $component.recipe.scriptSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "ffmpeg_source_missing_recipe:$id"
        }
        foreach ($patch in @($component.recipe.patches)) {
            if ([string]::IsNullOrWhiteSpace([string] $patch.path) -or [string] $patch.sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
                throw "ffmpeg_source_missing_patch:$id"
            }
        }
    }
    if ($components.Count -cne 122 -or $components.Count -cne [int] $Manifest.counts.btbnCacheArchives) {
        throw 'ffmpeg_source_cache_component_count_mismatch'
    }

    if (@($Graph.nestedClosures).Count -cne 19) { throw 'ffmpeg_source_nested_closure_count_mismatch' }
    foreach ($closure in @($Graph.nestedClosures)) {
        if ([string] $closure.applicability -cne 'conservative-superset' -or
            -not $components.ContainsKey(([string] $closure.componentId).ToLowerInvariant()) -or
            @($closure.gitmodules).Count -eq 0 -or @($closure.licenseFiles).Count -eq 0) {
            throw "ffmpeg_source_nested_closure_incomplete:$($closure.componentId)"
        }
    }

    $toolIds = @{}
    foreach ($component in @($Toolchain.components)) {
        $id = [string] $component.id
        $key = $id.ToLowerInvariant()
        if ($toolIds.ContainsKey($key)) { throw "ffmpeg_source_duplicate_component:$id" }
        $toolIds[$key] = $true
        $versionTag = [string] $component.source.url -match '/archive/refs/tags/v?[0-9]'
        if ([string] $component.applicability -cne 'conservative-superset' -or
            -not ((Test-ImmutableSourceUrl ([string] $component.source.url)) -or $versionTag)) {
            throw "ffmpeg_source_mutable_url:$id"
        }
        if ([string] $component.source.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "ffmpeg_source_missing_sha256:$id" }
        Assert-LicenseRecord $component.license $id $refs
        if ([string]::IsNullOrWhiteSpace([string] $component.recipe.dockerfilePath) -or
            [string]::IsNullOrWhiteSpace([string] $component.recipe.configPath)) {
            throw "ffmpeg_source_missing_recipe:$id"
        }
        foreach ($patch in @($component.recipe.patches)) {
            if ([string]::IsNullOrWhiteSpace([string] $patch.path) -or [string] $patch.sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
                throw "ffmpeg_source_missing_patch:$id"
            }
        }
    }
    foreach ($id in @('toolchain-gcc-16.2.0', 'toolchain-mingw-w64-v14.0.0', 'toolchain-crosstool-ng-b1a94f65')) {
        if (-not $toolIds.ContainsKey($id)) { throw "ffmpeg_source_missing_toolchain:$id" }
    }
    if ($toolIds.Count -cne 12 -or -not [bool] $Toolchain.crosstool.libgompEnabled) { throw 'ffmpeg_source_toolchain_incomplete' }
    if ([string] $Toolchain.baseImage.dockerfileInputStatus -cne 'mutable-upstream-input-retained-not-reproducibly-pinned') {
        throw 'ffmpeg_source_toolchain_provenance_overclaim'
    }

    if (@($Crates.components).Count -cne 270) { throw 'ffmpeg_source_crate_count_mismatch' }
    $crateIds = @{}
    $rav1eCorpus = @{}
    $rav1eReferenceCount = 0
    foreach ($record in @($Corpus.rav1eComponents)) {
        $recordId = [string] $record.componentId
        $recordKey = $recordId.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($recordId) -or $rav1eCorpus.ContainsKey($recordKey)) { throw "ffmpeg_source_duplicate_component:$recordId" }
        $rav1eCorpus[$recordKey] = $record
        $rav1eReferenceCount += @($record.licenseFiles).Count
    }
    if ($rav1eCorpus.Count -cne 270 -or $rav1eReferenceCount -cne 492 -or
        [int] $Corpus.textObjectCount -cne 681 -or [int] $Corpus.licenseFileReferenceCount -cne 1750) {
        throw 'ffmpeg_source_rav1e_license_corpus_incomplete'
    }
    foreach ($crate in @($Crates.components)) {
        $id = "$($crate.name)@$($crate.version)"
        $key = $id.ToLowerInvariant()
        if ($crateIds.ContainsKey($key)) { throw "ffmpeg_source_duplicate_component:$id" }
        $crateIds[$key] = $true
        if (-not (Test-ImmutableSourceUrl ([string] $crate.sourceUrl)) -or
            [string] $crate.sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
            [string]::IsNullOrWhiteSpace([string] $crate.licenseExpression) -or
            [string] $crate.licenseExpression -match 'NOASSERTION' -or @($crate.licenseTextPaths).Count -eq 0 -or
            -not $rav1eCorpus.ContainsKey($key)) {
            throw "ffmpeg_source_missing_license:$id"
        }
        $record = $rav1eCorpus[$key]
        if ([string] $record.sha256 -cne ([string] $crate.sha256).ToUpperInvariant() -or
            @($record.licenseFiles).Count -ne @($crate.licenseFiles).Count) { throw "ffmpeg_source_missing_license:$id" }
        $licenseFiles = @($crate.licenseFiles)
        if ($licenseFiles.Count -eq 0) {
            foreach ($textPath in @($crate.licenseTextPaths)) {
                if ([string] $textPath.kind -cne 'spdx-standard-text' -or
                    -not ([string] $textPath.path).StartsWith('licenses/spdx/', [StringComparison]::Ordinal) -or
                    @($Manifest.includedPaths) -cnotcontains [string] $textPath.path) {
                    throw "ffmpeg_source_missing_license:$id"
                }
            }
        }
        foreach ($file in $licenseFiles) {
            $sha = ([string] $file.sha256).ToUpperInvariant()
            $ref = [string] $file.licenseRef
            if (-not $refs.ContainsKey($sha) -or $refs[$sha] -cne $ref -or
                [string] $file.bundlePath -cne "licenses/extracted/$sha.txt" -or
                [string] $crate.licenseRefExpression -notmatch [regex]::Escape($ref)) {
                throw "ffmpeg_source_missing_license:$id"
            }
        }
    }

    $mapped = @{}
    foreach ($mapping in @($Manifest.enabledExternalLibraries)) {
        $option = [string] $mapping.option
        if ($mapped.ContainsKey($option)) { throw "ffmpeg_source_duplicate_option:$option" }
        if (-not $components.ContainsKey(([string] $mapping.componentId).ToLowerInvariant())) { throw "ffmpeg_source_unknown_component:$option" }
        $mapped[$option] = $true
    }
    foreach ($option in $Options) {
        if ((Test-ExternalBuildOption $option) -and -not $mapped.ContainsKey($option)) {
            throw "ffmpeg_source_unknown_enabled_library:$option"
        }
    }
}

function Read-FfmpegBinaryEvidence {
    param([string] $ArchivePath, [string] $ArchiveSha, [string] $FfmpegSha, [string] $FfprobeSha, [string] $ExpectedVersion)
    Assert-SourceArchiveHash $ArchivePath $ArchiveSha binary-archive
    $root = Join-Path ([IO.Path]::GetTempPath()) ('karon-ffmpeg-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root) | Out-Null
    try {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $root
        $ffmpeg = @(Get-ChildItem -LiteralPath $root -Filter ffmpeg.exe -File -Recurse)
        $ffprobe = @(Get-ChildItem -LiteralPath $root -Filter ffprobe.exe -File -Recurse)
        if ($ffmpeg.Count -cne 1 -or $ffprobe.Count -cne 1) { throw 'ffmpeg_source_binary_layout_mismatch' }
        Assert-SourceArchiveHash $ffmpeg[0].FullName $FfmpegSha ffmpeg
        Assert-SourceArchiveHash $ffprobe[0].FullName $FfprobeSha ffprobe
        $buildconf = @(& $ffmpeg[0].FullName -hide_banner -buildconf 2>&1 | ForEach-Object ToString)
        $version = @(& $ffmpeg[0].FullName -hide_banner -version 2>&1 | ForEach-Object ToString)
        if ($LASTEXITCODE -ne 0 -or $version[0] -notmatch ('^ffmpeg version ' + [regex]::Escape($ExpectedVersion) + '([-\s]|$)')) {
            throw 'ffmpeg_source_binary_version_mismatch'
        }
        [pscustomobject][ordered]@{
            archiveSha256 = Get-UpperSha256 $ArchivePath
            ffmpegSha256 = Get-UpperSha256 $ffmpeg[0].FullName
            ffprobeSha256 = Get-UpperSha256 $ffprobe[0].FullName
            versionLine = $version[0]
            configurationOptions = @($buildconf | ForEach-Object Trim | Where-Object { $_ -match '^--' })
            rawBuildConfiguration = $buildconf -join ([char]10)
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Add-FileToContentCache {
    param([string] $SourcePath, [string] $Sha, [string] $Id, [string] $Root)
    Assert-SourceArchiveHash $SourcePath $Sha $Id
    $shaUpper = $Sha.ToUpperInvariant()
    $directory = Join-Path (Join-Path $Root sha256) $shaUpper.Substring(0, 2)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $destination = Join-Path $directory $shaUpper
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        try { New-Item -ItemType HardLink -Path $destination -Target $SourcePath | Out-Null }
        catch { Copy-Item -LiteralPath $SourcePath -Destination $destination }
    }
    Assert-SourceArchiveHash $destination $shaUpper $Id
    $destination
}

function Get-VerifiedRemoteSource {
    param($Component, [string] $ContentRoot, [string] $SeedRoot)
    $id = [string] $Component.id
    $source = $Component.source
    $sha = ([string] $source.sha256).ToUpperInvariant()
    $directory = Join-Path (Join-Path $ContentRoot sha256) $sha.Substring(0, 2)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $destination = Join-Path $directory $sha
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        $seed = $null
        if ($SeedRoot -and $source.archiveName) {
            $candidate = Join-Path $SeedRoot ([string] $source.archiveName)
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $seed = $candidate }
        }
        if ($seed) { $destination = Add-FileToContentCache $seed $sha $id $ContentRoot }
        else {
            $versionTag = [string] $source.url -match '/archive/refs/tags/v?[0-9]'
            if (-not ((Test-ImmutableSourceUrl ([string] $source.url)) -or $versionTag)) { throw "ffmpeg_source_mutable_url:$id" }
            $temporary = $destination + '.partial.' + [Guid]::NewGuid().ToString('N')
            try {
                Invoke-WebRequest -UseBasicParsing -Uri ([string] $source.url) -OutFile $temporary
                Assert-SourceArchiveHash $temporary $sha $id
                Move-Item -LiteralPath $temporary -Destination $destination
            }
            finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        }
    }
    Assert-SourceArchiveHash $destination $sha $id
    [pscustomobject]@{ id = $id; sha256 = $sha; bytes = (Get-Item -LiteralPath $destination).Length; path = $destination; bundlePath = [string] $Component.bundlePath }
}

function New-BundleItem {
    param([string] $SourcePath, [string] $EntryPath, [string] $Sha)
    [pscustomobject]@{
        SourcePath = $SourcePath
        EntryPath = $EntryPath
        Sha256 = $(if ($Sha) { $Sha.ToUpperInvariant() } else { Get-UpperSha256 $SourcePath })
        Bytes = (Get-Item -LiteralPath $SourcePath).Length
    }
}

function Assert-OwnedBundleSnapshot {
    param($Snapshot)
    $root = [IO.Path]::GetFullPath([string] $Snapshot.Root)
    $parent = [IO.Path]::GetFullPath([string] $Snapshot.Parent).TrimEnd('\', '/')
    if ([IO.Path]::GetDirectoryName($root) -cne $parent -or
        -not [IO.Path]::GetFileName($root).StartsWith('ffmpeg-bundle-stage-', [StringComparison]::Ordinal)) {
        throw 'ffmpeg_source_snapshot_ownership_mismatch'
    }
    $marker = Join-Path $root '.owner'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
        [IO.File]::ReadAllText($marker, [Text.Encoding]::UTF8) -cne [string] $Snapshot.Token) {
        throw 'ffmpeg_source_snapshot_ownership_mismatch'
    }
    $root
}

function Remove-VerifiedBundleSnapshot {
    param($Snapshot)
    $root = Assert-OwnedBundleSnapshot $Snapshot
    Remove-Item -LiteralPath $root -Recurse -Force
}

function New-VerifiedBundleSnapshot {
    param([object[]] $Items, [string] $StagingParent, [string[]] $AllowedSourceRoots)
    $validated = @(Assert-BundleItems $Items $AllowedSourceRoots)
    $parent = [IO.Path]::GetFullPath($StagingParent)
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $token = [Guid]::NewGuid().ToString('N')
    $root = Join-Path $parent "ffmpeg-bundle-stage-$token"
    [IO.Directory]::CreateDirectory($root) | Out-Null
    [IO.File]::WriteAllText((Join-Path $root '.owner'), $token, [Text.UTF8Encoding]::new($false))
    $snapshot = [pscustomobject][ordered]@{ Root = $root; Parent = $parent; Token = $token; Items = @() }
    try {
        $staged = @()
        $index = 0
        foreach ($item in @($validated | Sort-Object @{Expression = { $_.EntryPath.ToLowerInvariant() }}, @{Expression = { $_.EntryPath }})) {
            $destination = Join-Path $root ('{0:D8}.bin' -f $index)
            $input = [IO.File]::Open($item.SourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $output = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
            $actualBytes = (Get-Item -LiteralPath $destination).Length
            $actualSha = Get-UpperSha256 $destination
            if ($actualSha -cne $item.Sha256 -or $actualBytes -ne $item.Bytes) {
                throw "ffmpeg_source_staged_sha256_mismatch:$($item.EntryPath)"
            }
            $staged += [pscustomobject][ordered]@{
                SourcePath = $destination
                EntryPath = $item.EntryPath
                Sha256 = $actualSha
                Bytes = $actualBytes
            }
            $index++
        }
        $snapshot.Items = $staged
        $snapshot
    }
    catch {
        Remove-VerifiedBundleSnapshot $snapshot
        throw
    }
}

function Assert-ZipMatchesItems {
    param([string] $ZipPath, [object[]] $Items)
    Add-Type -AssemblyName System.IO.Compression
    $expected = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($item in $Items) {
        $path = Assert-SafeBundlePath ([string] $item.EntryPath)
        if ($expected.ContainsKey($path)) { throw "ffmpeg_source_duplicate_path:$path" }
        $expected.Add($path, $item)
    }
    $stream = [IO.File]::Open($ZipPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            if ($archive.Entries.Count -ne $expected.Count) { throw 'ffmpeg_source_zip_entry_count_mismatch' }
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($entry in $archive.Entries) {
                $path = Assert-SafeBundlePath $entry.FullName
                if (-not $seen.Add($path) -or -not $expected.ContainsKey($path)) { throw "ffmpeg_source_zip_path_mismatch:$path" }
                $item = $expected[$path]
                if ($entry.Length -ne [int64] $item.Bytes) { throw "ffmpeg_source_zip_length_mismatch:$path" }
                $entryStream = $entry.Open()
                $algorithm = [Security.Cryptography.SHA256]::Create()
                try { $sha = [Convert]::ToHexString($algorithm.ComputeHash($entryStream)) }
                finally { $algorithm.Dispose(); $entryStream.Dispose() }
                if ($sha -cne ([string] $item.Sha256).ToUpperInvariant()) { throw "ffmpeg_source_zip_sha256_mismatch:$path" }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
    [pscustomobject][ordered]@{ verifiedEntryCount = $expected.Count }
}

function Write-DeterministicZipFromSnapshot {
    param($Snapshot, [string] $OutputPath)
    $root = Assert-OwnedBundleSnapshot $Snapshot
    $items = @(Assert-BundleItems $Snapshot.Items @($root))
    Add-Type -AssemblyName System.IO.Compression
    $created = $false
    try {
        $stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $created = $true
        try {
            $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
            try {
                foreach ($item in $items) {
                    $entry = $archive.CreateEntry($item.EntryPath, [IO.Compression.CompressionLevel]::NoCompression)
                    $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                    $input = [IO.File]::Open($item.SourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                    $output = $entry.Open()
                    try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
                }
            }
            finally { $archive.Dispose() }
        }
        finally { $stream.Dispose() }
        Assert-ZipMatchesItems $OutputPath $items
    }
    catch {
        if ($created -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { Remove-Item -LiteralPath $OutputPath -Force }
        throw
    }
}

function New-DeterministicZip {
    param([object[]] $Items, [string] $OutputPath, [string[]] $AllowedSourceRoots)
    $parent = Split-Path -Parent $OutputPath
    if ([string]::IsNullOrWhiteSpace($parent)) { $parent = (Get-Location).Path }
    $snapshot = New-VerifiedBundleSnapshot $Items $parent $AllowedSourceRoots
    try { Write-DeterministicZipFromSnapshot $snapshot $OutputPath }
    finally { Remove-VerifiedBundleSnapshot $snapshot }
}

function Invoke-FfmpegSourceCollector {
    param([string] $InputManifestPath, [string] $InputBinaryArchivePath, [string] $OutputRoot, [string] $ContentRoot)
    $manifest = Get-Content -Raw -LiteralPath $InputManifestPath | ConvertFrom-Json
    if ([int] $manifest.schemaVersion -cne 3) { throw 'ffmpeg_source_manifest_schema_unsupported' }
    $manifestRoot = Split-Path -Parent (Resolve-Path -LiteralPath $InputManifestPath)
    $graph = Get-Content -Raw -LiteralPath (Join-Path $manifestRoot $manifest.sourceSets.btbnActionsCache.componentGraphPath) | ConvertFrom-Json
    $crates = Get-Content -Raw -LiteralPath (Join-Path $manifestRoot $manifest.sourceSets.rav1eCrates.manifestPath) | ConvertFrom-Json
    $toolchain = Get-Content -Raw -LiteralPath (Join-Path $manifestRoot $manifest.sourceSets.toolchain.manifestPath) | ConvertFrom-Json
    $corpus = Get-Content -Raw -LiteralPath (Join-Path $manifestRoot $manifest.sourceSets.licenseCorpus.manifestPath) | ConvertFrom-Json
    [IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
    [IO.Directory]::CreateDirectory($ContentRoot) | Out-Null

    $evidence = Read-FfmpegBinaryEvidence $InputBinaryArchivePath $manifest.binary.archiveSha256 $manifest.binary.ffmpegSha256 $manifest.binary.ffprobeSha256 $manifest.binary.expectedVersion
    $expected = @(Get-Content -LiteralPath (Join-Path $manifestRoot $manifest.binary.buildConfigurationPath) | ForEach-Object Trim | Where-Object { $_ -match '^--' })
    if (($expected -join ([char]10)) -cne ($evidence.configurationOptions -join ([char]10))) { throw 'ffmpeg_source_build_configuration_mismatch' }
    Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus $evidence.configurationOptions
    $null = Assert-LicenseCorpus $corpus $manifestRoot -VerifyFiles
    $gitLicenseEvidence = Assert-GitLicenseCorpus $corpus $manifestRoot HEAD
    $binaryEvidencePath = Join-Path $OutputRoot binary-evidence.json
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $binaryEvidencePath -Encoding utf8NoBOM

    $sources = @()
    foreach ($name in @('ffmpeg', 'btbnScripts', 'spdxLicenseList')) {
        $sources += Get-VerifiedRemoteSource ([pscustomobject]@{ id = $name; source = $manifest.sourceSets.$name; bundlePath = "sources/direct/$name.source" }) $ContentRoot
    }
    $cacheFiles = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $BtbNCacheRoot -File -Recurse)) {
        if ($cacheFiles.ContainsKey($file.Name)) { $cacheFiles[$file.Name] = $null } else { $cacheFiles[$file.Name] = $file.FullName }
    }
    foreach ($component in @($graph.components)) {
        $name = [string] $component.source.archiveName
        if (-not $cacheFiles.ContainsKey($name) -or -not $cacheFiles[$name]) { throw "ffmpeg_source_missing_archive:$($component.id)" }
        $path = Add-FileToContentCache $cacheFiles[$name] $component.source.sha256 $component.id $ContentRoot
        $sources += [pscustomobject]@{ id = $component.id; sha256 = $component.source.sha256.ToUpperInvariant(); bytes = $component.source.bytes; path = $path; bundlePath = "sources/btbn-cache/$name" }
    }
    foreach ($crate in @($crates.components)) {
        $id = "crate:$($crate.name)@$($crate.version)"
        $path = Add-FileToContentCache (Join-Path $Rav1eCrateCacheRoot ([string] $crate.cachePath)) $crate.sha256 $id $ContentRoot
        $sources += [pscustomobject]@{ id = $id; sha256 = $crate.sha256.ToUpperInvariant(); bytes = $crate.bytes; path = $path; bundlePath = "sources/rav1e-crates/$($crate.name)-$($crate.version)-$($crate.sha256).crate" }
    }
    foreach ($tool in @($toolchain.components)) {
        $sources += Get-VerifiedRemoteSource ([pscustomobject]@{ id = $tool.id; source = $tool.source; bundlePath = "sources/toolchain/$($tool.source.archiveName)" }) $ContentRoot $ToolchainSourceRoot
    }
    if ($sources.Count -cne [int] $manifest.counts.totalSourceArchives) { throw 'ffmpeg_source_inventory_count_mismatch' }

    $items = @($sources | ForEach-Object { New-BundleItem $_.path $_.bundlePath $_.sha256 })
    $items += New-BundleItem $InputManifestPath manifest.json
    $items += New-BundleItem $binaryEvidencePath evidence/collector-binary-evidence.json
    foreach ($relative in @($manifest.includedPaths)) {
        $relative = Assert-SafeBundlePath ([string] $relative)
        $path = Join-Path $manifestRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "ffmpeg_source_missing_included_path:$relative" }
        $items += New-BundleItem $path $relative
    }
    foreach ($text in @($corpus.textObjects)) {
        $path = Join-Path $manifestRoot ([string] $text.bundlePath)
        $items += New-BundleItem $path ([string] $text.bundlePath) ([string] $text.sha256)
    }

    $inventoryPath = Join-Path $OutputRoot inventory.json
    [pscustomobject][ordered]@{
        schemaVersion = 1
        policy = 'verified-conservative-superset'
        sourceArchiveCount = $sources.Count
        cacheArchiveCount = 122
        rav1eCrateCount = 270
        toolchainSourceCount = 12
        licenseTextObjectCount = $corpus.textObjectCount
        inventorySelfEntry = 'inventory.json'
        entries = @($items | Sort-Object @{Expression = { $_.EntryPath.ToLowerInvariant() }}, @{Expression = { $_.EntryPath }} | ForEach-Object {
            [pscustomobject][ordered]@{ path = $_.EntryPath; bytes = $_.Bytes; sha256 = $_.Sha256 }
        })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inventoryPath -Encoding utf8NoBOM
    $items += New-BundleItem $inventoryPath inventory.json
    $bundle = Join-Path $OutputRoot 'ytdlp-korean-interface-v2.19.1-karon.2-ffmpeg-corresponding-sources.zip'
    $zipVerification = New-DeterministicZip $items $bundle @($ContentRoot, $manifestRoot, $OutputRoot)

    $result = [pscustomobject][ordered]@{
        status = 'complete'
        closurePolicy = 'verified-conservative-superset'
        sourceCount = $sources.Count
        componentCount = $graph.componentCount
        rav1eCrateCount = $crates.componentCount
        toolchainSourceCount = $toolchain.componentCount
        licenseTextObjectCount = $corpus.textObjectCount
        nestedClosureCount = $graph.nestedClosureCount
        inventoryEntryCount = $items.Count
        verifiedGitLicenseBlobCount = $gitLicenseEvidence.verifiedBlobCount
        verifiedZipEntryCount = $zipVerification.verifiedEntryCount
        bundlePath = $bundle
        bundleBytes = (Get-Item -LiteralPath $bundle).Length
        bundleSha256 = Get-UpperSha256 $bundle
        inventoryPath = $inventoryPath
        blockers = @()
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot collector-result.json) -Encoding utf8NoBOM
    $result
}

if (-not $NoExecute) {
    if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $ScratchRoot cache }
    Invoke-FfmpegSourceCollector $ManifestPath $BinaryArchivePath $ScratchRoot $CacheRoot
}
