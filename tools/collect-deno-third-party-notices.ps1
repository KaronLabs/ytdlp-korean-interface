#requires -Version 7.4
[CmdletBinding()]
param(
    [string] $ManifestRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'release/runtime/v2.19.1-karon.2/deno'),
    [string] $DenoSourceRoot,
    [string] $RustyV8SourceRoot,
    [string] $V8SourceRoot,
    [string] $VendorRoot,
    [string] $OfficialMetadataPath,
    [string] $SupersetMetadataPath,
    [string] $DenoExePath,
    [string] $DenoSourceArchivePath,
    [string] $RustyV8SourceArchivePath,
    [string] $V8SourceArchivePath,
    [string] $RustyV8StaticLibArchivePath,
    [string] $NativeSourceRoot,
    [string] $CrateArchiveRoot,
    [string] $SpdxRoot,
    [string] $SpdxArchivePath,
    [string] $UpstreamSourceRoot,
    [string] $UpstreamFallbackManifest,
    [string] $ScratchRoot,
    [switch] $Run
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DenoSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-DenoUtf8Text {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Text)
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function Read-DenoJson {
    param([Parameter(Mandatory)] [string] $Path)
    $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    return ConvertFrom-Json -InputObject $raw -Depth 100
}

function Assert-DenoHash {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $ExpectedSha256)
    if ($ExpectedSha256 -notmatch '^[0-9a-f]{64}$' -or (Get-DenoSha256 $Path) -cne $ExpectedSha256) {
        throw "deno_input_hash_mismatch:$Path"
    }
}

function Assert-DenoImmutableCargoSource {
    param([Parameter(Mandatory)] [string] $Source)
    if ($Source -ceq 'registry+https://github.com/rust-lang/crates.io-index') { return $true }
    if ($Source.StartsWith('git+', [StringComparison]::Ordinal)) {
        if ($Source -match '(?i)[?&](branch|tag)=' -or
            $Source -notmatch '#(?<commit>[0-9a-f]{40})$' -or
            ($Source -match '[?&]rev=(?<revision>[0-9a-f]{40})(?:&|#)' -and $Matches.revision -cne $Matches.commit)) {
            throw 'deno_mutable_git_source'
        }
        return $true
    }
    throw 'deno_unsupported_cargo_source'
}

function Assert-DenoUniquePaths {
    param([Parameter(Mandatory)] [string[]] $Paths)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($inputPath in $Paths) {
        $path = $inputPath.Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($path) -or $path.StartsWith('/') -or
            $path -match '^[A-Za-z]:' -or $path.Contains([char]0) -or
            @($path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
            throw "deno_path_invalid:$path"
        }
        if (-not $seen.Add($path)) { throw "deno_path_case_collision:$($path.ToLowerInvariant())" }
    }
    return $true
}

function Assert-DenoNativeClosure {
    param(
        [Parameter(Mandatory)] [string[]] $RequiredComponents,
        [Parameter(Mandatory)] [string[]] $ObservedComponents
    )
    $observed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($component in $ObservedComponents) { [void]$observed.Add($component) }
    foreach ($component in $RequiredComponents | Sort-Object) {
        if (-not $observed.Contains($component)) { throw "deno_native_component_missing:$component" }
    }
    return $true
}

function Assert-DenoTargetClosure {
    param(
        [Parameter(Mandatory)] [string[]] $OfficialPackageIds,
        [Parameter(Mandatory)] [string[]] $SupersetPackageIds
    )
    $superset = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $SupersetPackageIds) { [void]$superset.Add($packageId) }
    foreach ($id in $OfficialPackageIds | Sort-Object -Unique) {
        if (-not $superset.Contains($id)) { throw "deno_target_closure_mismatch:$id" }
    }
    return $true
}

function Assert-DenoReleaseIdentity {
    param(
        [Parameter(Mandatory)] [string] $DenoExePath,
        [Parameter(Mandatory)] [string] $ExpectedSha256,
        [Parameter(Mandatory)] [string] $ExpectedVersion,
        [Parameter(Mandatory)] [string] $ExpectedTarget
    )
    Assert-DenoHash $DenoExePath $ExpectedSha256
    $lines = @(& $DenoExePath --version 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 1 -or
        $lines[0] -notmatch '^deno (?<version>[^ ]+) \(stable, release, (?<target>[^)]+)\)$' -or
        $Matches.version -cne $ExpectedVersion -or $Matches.target -cne $ExpectedTarget) {
        throw 'deno_release_identity_mismatch'
    }
    return [pscustomobject]@{ version = $Matches.version; target = $Matches.target; sha256 = $ExpectedSha256 }
}

function Get-DenoLicenseFiles {
    param([Parameter(Mandatory)] [string] $Root, [string] $DeclaredLicenseFile)
    $files = [Collections.Generic.List[IO.FileInfo]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
        if ($file.Name -match '^(?i:LICENSE|LICENCE|COPYING|NOTICE|PATENTS|COPYRIGHT)(?:[._-].*)?$') { $files.Add($file) }
    }
    if (-not [string]::IsNullOrWhiteSpace($DeclaredLicenseFile)) {
        $declared = [IO.Path]::GetFullPath((Join-Path $Root $DeclaredLicenseFile))
        $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        if (-not $declared.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $declared -PathType Leaf)) {
            throw 'deno_declared_license_file_missing'
        }
        if ($files.FullName -notcontains $declared) { $files.Add((Get-Item -LiteralPath $declared)) }
    }
    return @($files | Sort-Object FullName -Unique)
}

function Get-DenoSpdxIndex {
    param([Parameter(Mandatory)] [string] $SpdxRoot)
    $licenses = Read-DenoJson (Join-Path $SpdxRoot 'json/licenses.json')
    $exceptions = Read-DenoJson (Join-Path $SpdxRoot 'json/exceptions.json')
    if ([string]$licenses.licenseListVersion -cne [string]$exceptions.licenseListVersion) { throw 'deno_spdx_version_mismatch' }
    $licenseMap = @{}
    foreach ($item in $licenses.licenses) { $licenseMap[[string]$item.licenseId] = $item }
    $exceptionMap = @{}
    foreach ($item in $exceptions.exceptions) { $exceptionMap[[string]$item.licenseExceptionId] = $item }
    return [pscustomobject]@{ version = [string]$licenses.licenseListVersion; licenses = $licenseMap; exceptions = $exceptionMap }
}

function Resolve-DenoSpdxExpression {
    param([Parameter(Mandatory)] [string] $Expression, [Parameter(Mandatory)] [string] $SpdxRoot)
    $failure = "deno_spdx_expression_invalid:$Expression"
    if ([string]::IsNullOrWhiteSpace($Expression) -or $Expression -match '(?i)NOASSERTION|UNKNOWN|LicenseRef-|DocumentRef-') { throw $failure }
    $index = Get-DenoSpdxIndex $SpdxRoot
    $tokens = [Collections.Generic.List[string]]::new()
    $position = 0
    $tokenPattern = [regex]::new('\G\s*(?<token>\(|\)|AND(?=\s|\()|OR(?=\s|\()|WITH(?=\s|\()|[A-Za-z0-9][A-Za-z0-9.+-]*)', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    while ($position -lt $Expression.Length) {
        $match = $tokenPattern.Match($Expression, $position)
        if (-not $match.Success -or $match.Index -ne $position -or [string]::IsNullOrWhiteSpace($match.Groups['token'].Value)) {
            if ($Expression.Substring($position) -match '^\s+$') { $position = $Expression.Length; break }
            throw $failure
        }
        $tokens.Add($match.Groups['token'].Value)
        $position += $match.Length
    }
    if ($tokens.Count -eq 0) { throw $failure }

    $state = [pscustomobject]@{ index = 0 }
    $licenseIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $exceptionIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $parseOr = $null
    $parsePrimary = {
        if ($state.index -ge $tokens.Count) { throw $failure }
        $token = $tokens[$state.index]
        if ($token -ceq '(') {
            $state.index++
            & $parseOr
            if ($state.index -ge $tokens.Count -or $tokens[$state.index] -cne ')') { throw $failure }
            $state.index++
            return
        }
        if ($token -in @(')', 'AND', 'OR', 'WITH') -or -not $index.licenses.ContainsKey($token)) { throw $failure }
        [void]$licenseIds.Add($token)
        $state.index++
        if ($state.index -lt $tokens.Count -and $tokens[$state.index] -ceq 'WITH') {
            $state.index++
            if ($state.index -ge $tokens.Count -or -not $index.exceptions.ContainsKey($tokens[$state.index])) { throw $failure }
            [void]$exceptionIds.Add($tokens[$state.index])
            $state.index++
        }
    }
    $parseAnd = {
        & $parsePrimary
        while ($state.index -lt $tokens.Count -and $tokens[$state.index] -ceq 'AND') { $state.index++; & $parsePrimary }
    }
    $parseOr = {
        & $parseAnd
        while ($state.index -lt $tokens.Count -and $tokens[$state.index] -ceq 'OR') { $state.index++; & $parseAnd }
    }
    & $parseOr
    if ($state.index -ne $tokens.Count) { throw $failure }

    $files = [Collections.Generic.List[object]]::new()
    foreach ($id in @($licenseIds | Sort-Object)) {
        $path = "text/$id.txt"
        $fullPath = Join-Path $SpdxRoot $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "deno_spdx_text_missing:$id" }
        $files.Add([ordered]@{ origin = 'spdx-license'; id = $id; path = $path; length = (Get-Item $fullPath).Length; sha256 = Get-DenoSha256 $fullPath })
    }
    foreach ($id in @($exceptionIds | Sort-Object)) {
        $path = "text/$id.txt"
        $fullPath = Join-Path $SpdxRoot $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "deno_spdx_exception_text_missing:$id" }
        $files.Add([ordered]@{ origin = 'spdx-exception'; id = $id; path = $path; length = (Get-Item $fullPath).Length; sha256 = Get-DenoSha256 $fullPath })
    }
    return [pscustomobject]@{ version = $index.version; licenseIds = @($licenseIds | Sort-Object); exceptionIds = @($exceptionIds | Sort-Object); files = @($files) }
}

function Assert-DenoVendorChecksums {
    param([Parameter(Mandatory)] [string] $VendorPath, [Parameter(Mandatory)] [object] $Checksum, [Parameter(Mandatory)] [string] $Id)
    $declaredPaths = @($Checksum.files.psobject.Properties.Name)
    Assert-DenoUniquePaths $declaredPaths | Out-Null
    $declared = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $declaredPaths) {
        [void]$declared.Add($path.Replace('\', '/'))
        $fullPath = Join-Path $VendorPath $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf) -or (Get-DenoSha256 $fullPath) -cne [string]$Checksum.files.$path) {
            throw "deno_vendor_file_checksum_mismatch:$Id`:$path"
        }
    }
    foreach ($file in Get-ChildItem -LiteralPath $VendorPath -Recurse -File -Force) {
        $relative = $file.FullName.Substring([IO.Path]::GetFullPath($VendorPath).TrimEnd('\').Length + 1).Replace('\', '/')
        if ($relative -cne '.cargo-checksum.json' -and -not $declared.Contains($relative)) { throw "deno_vendor_unchecksummed_file:$Id`:$relative" }
    }
}

function Get-DenoZipEntrySha256 {
    param([Parameter(Mandatory)] [string] $ArchivePath, [Parameter(Mandatory)] [string] $EntryPath)
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entries = @($zip.Entries | Where-Object { $_.FullName -ceq $EntryPath })
        if ($entries.Count -ne 1) { throw "deno_upstream_license_entry_missing:$EntryPath" }
        $stream = $entries[0].Open()
        try { $hash = [Security.Cryptography.SHA256]::Create(); try { return ([Convert]::ToHexString($hash.ComputeHash($stream))).ToLowerInvariant() } finally { $hash.Dispose() } } finally { $stream.Dispose() }
    }
    finally { $zip.Dispose() }
}

function Copy-DenoZipEntry {
    param([Parameter(Mandatory)] [string] $ArchivePath, [Parameter(Mandatory)] [string] $EntryPath, [Parameter(Mandatory)] [string] $Destination)
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entries = @($zip.Entries | Where-Object { $_.FullName -ceq $EntryPath })
        if ($entries.Count -ne 1) { throw "deno_upstream_license_entry_missing:$EntryPath" }
        New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $Destination, $false)
    }
    finally { $zip.Dispose() }
}

function Copy-DenoTarEntry {
    param([Parameter(Mandatory)] [string] $ArchivePath, [Parameter(Mandatory)] [string] $EntryPath, [Parameter(Mandatory)] [string] $Destination)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'tar.exe'
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.ArgumentList.Add('-xOf')
    $start.ArgumentList.Add($ArchivePath)
    $start.ArgumentList.Add($EntryPath)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw "deno_native_license_extract_failed:$EntryPath" }
    $output = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $process.StandardOutput.BaseStream.CopyTo($output) } finally { $output.Dispose() }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "deno_native_license_extract_failed:$EntryPath" }
    $process.Dispose()
}

function Resolve-DenoUpstreamFallback {
    param([Parameter(Mandatory)] [object] $Fallback, [Parameter(Mandatory)] [string] $UpstreamSourceRoot)
    $archive = Join-Path $UpstreamSourceRoot ([string]$Fallback.archiveFile)
    $item = Get-Item -LiteralPath $archive
    if ($item.Length -ne [long]$Fallback.length) { throw "deno_upstream_archive_length_mismatch:$($Fallback.id)" }
    Assert-DenoHash $archive ([string]$Fallback.sha256)
    $files = [Collections.Generic.List[object]]::new()
    foreach ($license in $Fallback.licenseFiles) {
        $actual = Get-DenoZipEntrySha256 -ArchivePath $archive -EntryPath ([string]$license.path)
        if ($actual -cne [string]$license.sha256) { throw "deno_upstream_license_hash_mismatch:$($Fallback.id):$($license.path)" }
        $files.Add([ordered]@{ origin = 'upstream-commit'; path = [string]$license.path; length = [long]$license.length; sha256 = $actual; archiveFile = [string]$Fallback.archiveFile })
    }
    if ($files.Count -eq 0) { throw "deno_upstream_license_file_missing:$($Fallback.id)" }
    return [pscustomobject]@{ files = @($files); provenance = $Fallback }
}

function Assert-DenoCratePackage {
    param(
        [Parameter(Mandatory)] [object] $Package,
        [Parameter(Mandatory)] [string] $VendorPath,
        [string] $CrateArchivePath,
        [string] $SpdxRoot,
        [object] $UpstreamFallback,
        [string] $UpstreamSourceRoot
    )
    $id = ([string]$Package.name) + '@' + ([string]$Package.version)
    Assert-DenoImmutableCargoSource ([string]$Package.source) | Out-Null
    if ([string]$Package.checksum -notmatch '^[0-9a-f]{64}$') { throw "deno_cargo_checksum_missing:$id" }
    $checksum = Read-DenoJson (Join-Path $VendorPath '.cargo-checksum.json')
    if ([string]$checksum.package -cne [string]$Package.checksum) { throw "deno_cargo_checksum_mismatch:$id" }
    if (-not [string]::IsNullOrWhiteSpace($CrateArchivePath)) {
        Assert-DenoVendorChecksums -VendorPath $VendorPath -Checksum $checksum -Id $id
        Assert-DenoHash $CrateArchivePath ([string]$Package.checksum)
    }

    $toml = [IO.File]::ReadAllText((Join-Path $VendorPath 'Cargo.toml'), [Text.UTF8Encoding]::new($false, $true))
    $license = [regex]::Match($toml, '(?m)^license\s*=\s*"([^"]+)"').Groups[1].Value
    $licenseFile = [regex]::Match($toml, '(?m)^license-file\s*=\s*"([^"]+)"').Groups[1].Value
    $repository = [regex]::Match($toml, '(?m)^repository\s*=\s*"([^"]+)"').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($license) -and [string]::IsNullOrWhiteSpace($licenseFile)) {
        throw "deno_crate_license_metadata_missing:$id"
    }
    if ($license -match '(?i)NOASSERTION|UNKNOWN') { throw "deno_crate_license_ambiguous:$id" }
    $files = @(Get-DenoLicenseFiles -Root $VendorPath -DeclaredLicenseFile $licenseFile)
    $root = [IO.Path]::GetFullPath($VendorPath).TrimEnd('\')
    $records = @($files | ForEach-Object {
        $file = $_
        [ordered]@{
            origin = 'package'
            path = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
            length = $file.Length
            sha256 = Get-DenoSha256 $file.FullName
        }
    })
    if ($records.Count -gt 0) {
        return [pscustomobject]@{ id = $id; license = $license; licenseFile = $licenseFile; repository = $repository; resolution = 'package-files'; resolvedLicenseFiles = $records; spdxLicenseIds = @(); spdxExceptionIds = @(); provenance = $null }
    }
    if (-not [string]::IsNullOrWhiteSpace($SpdxRoot)) {
        try {
            $spdx = Resolve-DenoSpdxExpression -Expression $license -SpdxRoot $SpdxRoot
            return [pscustomobject]@{ id = $id; license = $license; licenseFile = $licenseFile; repository = $repository; resolution = 'spdx-canonical-fallback'; resolvedLicenseFiles = @($spdx.files); spdxLicenseIds = @($spdx.licenseIds); spdxExceptionIds = @($spdx.exceptionIds); provenance = [ordered]@{ spdxVersion = $spdx.version } }
        }
        catch {
            if ($null -eq $UpstreamFallback) { throw }
        }
    }
    if ($null -ne $UpstreamFallback -and -not [string]::IsNullOrWhiteSpace($UpstreamSourceRoot)) {
        $upstream = Resolve-DenoUpstreamFallback -Fallback $UpstreamFallback -UpstreamSourceRoot $UpstreamSourceRoot
        return [pscustomobject]@{ id = $id; license = $license; licenseFile = $licenseFile; repository = $repository; resolution = 'upstream-commit-license-files'; resolvedLicenseFiles = @($upstream.files); spdxLicenseIds = @(); spdxExceptionIds = @(); provenance = $upstream.provenance }
    }
    throw "deno_crate_license_file_missing:$id"
}

function Read-DenoCargoLockPackages {
    param([Parameter(Mandatory)] [string] $CargoLockPath)
    $raw = [IO.File]::ReadAllText($CargoLockPath, [Text.UTF8Encoding]::new($false, $true))
    $packages = [Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($raw, '(?ms)^\[\[package\]\]\r?\n(.*?)(?=^\[\[package\]\]|\z)')) {
        $block = $match.Groups[1].Value
        $name = [regex]::Match($block, '(?m)^name = "([^"]+)"').Groups[1].Value
        $version = [regex]::Match($block, '(?m)^version = "([^"]+)"').Groups[1].Value
        $source = [regex]::Match($block, '(?m)^source = "([^"]+)"').Groups[1].Value
        $checksum = [regex]::Match($block, '(?m)^checksum = "([0-9a-f]{64})"').Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($version)) { throw 'deno_cargo_lock_parse_failed' }
        if (-not [string]::IsNullOrWhiteSpace($source)) { Assert-DenoImmutableCargoSource $source | Out-Null }
        $packages.Add([pscustomobject]@{ name = $name; version = $version; source = $source; checksum = $checksum })
    }
    if ($packages.Count -eq 0) { throw 'deno_cargo_lock_empty' }
    return @($packages)
}

function Get-DenoMetadataPackageIds {
    param([Parameter(Mandatory)] [object] $Metadata)
    return @($Metadata.packages | ForEach-Object { ([string]$_.name) + '@' + ([string]$_.version) } | Sort-Object -Unique)
}

function Write-DenoBlockerReport {
    param(
        [Parameter(Mandatory)] [string] $ScratchRoot,
        [Parameter(Mandatory)] [object] $Identity,
        [Parameter(Mandatory)] [string[]] $Blockers,
        [Parameter(Mandatory)] [hashtable] $Counts,
        [object[]] $UnresolvedEvidence = @()
    )
    $report = [ordered]@{
        schemaVersion = 'deno-third-party-collection-blockers/v1'
        status = 'NOT_VERIFIED'
        closureClassification = 'verified-conservative-superset'
        releaseIdentity = $Identity
        counts = [ordered]@{
            cargoLockPackages = $Counts.cargoLockPackages
            registryPackages = $Counts.registryPackages
            resolvedRegistryPackages = $Counts.resolvedRegistryPackages
            registryPackageFileResolutions = $Counts.registryPackageFileResolutions
            registrySpdxResolutions = $Counts.registrySpdxResolutions
            registryUpstreamResolutions = $Counts.registryUpstreamResolutions
            workspacePackages = $Counts.workspacePackages
            resolvedWorkspacePackages = $Counts.resolvedWorkspacePackages
            workspaceSpdxResolutions = $Counts.workspaceSpdxResolutions
            workspaceUpstreamResolutions = $Counts.workspaceUpstreamResolutions
            nativeComponents = $Counts.nativeComponents
        }
        blockers = @($Blockers | Sort-Object -Unique)
        unresolvedEvidence = @($UnresolvedEvidence | Sort-Object id)
        noticeArtifactProduced = $false
        sourceBundleProduced = $false
        overallReleasePass = $false
    }
    $path = Join-Path $ScratchRoot 'deno-collection-blockers.json'
    Write-DenoUtf8Text $path (($report | ConvertTo-Json -Depth 10) + "`n")
    return $path
}

function New-DenoDeterministicZip {
    param([Parameter(Mandatory)] [string] $SourceRoot, [Parameter(Mandatory)] [string] $ZipPath)
    $root = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Sort-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
    $relative = @($files | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
    Assert-DenoUniquePaths $relative | Out-Null
    $stream = [IO.File]::Open($ZipPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            for ($index = 0; $index -lt $files.Count; $index++) {
                $entry = $zip.CreateEntry($relative[$index], [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $input = [IO.File]::OpenRead($files[$index].FullName)
                try { $output = $entry.Open(); try { $input.CopyTo($output) } finally { $output.Dispose() } } finally { $input.Dispose() }
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }
    return Get-DenoSha256 $ZipPath
}

function Invoke-DenoThirdPartyNoticeCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ManifestRoot,
        [Parameter(Mandatory)] [string] $DenoSourceRoot,
        [Parameter(Mandatory)] [string] $RustyV8SourceRoot,
        [Parameter(Mandatory)] [string] $V8SourceRoot,
        [Parameter(Mandatory)] [string] $VendorRoot,
        [Parameter(Mandatory)] [string] $OfficialMetadataPath,
        [Parameter(Mandatory)] [string] $SupersetMetadataPath,
        [Parameter(Mandatory)] [string] $DenoExePath,
        [Parameter(Mandatory)] [string] $DenoSourceArchivePath,
        [Parameter(Mandatory)] [string] $RustyV8SourceArchivePath,
        [Parameter(Mandatory)] [string] $V8SourceArchivePath,
        [Parameter(Mandatory)] [string] $RustyV8StaticLibArchivePath,
        [Parameter(Mandatory)] [string] $NativeSourceRoot,
        [Parameter(Mandatory)] [string] $CrateArchiveRoot,
        [Parameter(Mandatory)] [string] $SpdxRoot,
        [Parameter(Mandatory)] [string] $SpdxArchivePath,
        [Parameter(Mandatory)] [string] $UpstreamSourceRoot,
        [Parameter(Mandatory)] [string] $UpstreamFallbackManifest,
        [Parameter(Mandatory)] [string] $ScratchRoot
    )
    $inputs = Read-DenoJson (Join-Path $ManifestRoot 'inputs.json')
    $native = Read-DenoJson (Join-Path $ManifestRoot 'native-components.json')
    $fallbacks = Read-DenoJson $UpstreamFallbackManifest
    if ($inputs.schemaVersion -cne 'deno-third-party-inputs/v2' -or
        $fallbacks.schemaVersion -cne 'deno-license-fallbacks/v1' -or
        $inputs.closureClassification -cne 'verified-conservative-superset') { throw 'deno_input_manifest_invalid' }
    New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null
    $identity = Assert-DenoReleaseIdentity -DenoExePath $DenoExePath -ExpectedSha256 $inputs.releaseIdentity.denoExeSha256 -ExpectedVersion $inputs.releaseIdentity.version -ExpectedTarget $inputs.releaseIdentity.target

    $artifactPaths = @{
        denoSource = $DenoSourceArchivePath; rustyV8Source = $RustyV8SourceArchivePath
        v8Source = $V8SourceArchivePath; rustyV8StaticLibrary = $RustyV8StaticLibArchivePath
        spdxLicenseListData = $SpdxArchivePath
    }
    foreach ($artifact in $inputs.sourceArtifacts) {
        $path = [string]$artifactPaths[[string]$artifact.id]
        if ([string]::IsNullOrWhiteSpace($path)) { throw "deno_source_artifact_unmapped:$($artifact.id)" }
        $item = Get-Item -LiteralPath $path
        if ($item.Length -ne [long]$artifact.length) { throw "deno_source_artifact_length_mismatch:$($artifact.id)" }
        Assert-DenoHash $path ([string]$artifact.sha256)
    }
    foreach ($pinned in $inputs.pinnedSourceFiles) {
        $base = switch ([string]$pinned.root) { 'deno' { $DenoSourceRoot } 'rusty_v8' { $RustyV8SourceRoot } 'v8' { $V8SourceRoot } 'spdx' { $SpdxRoot } default { throw 'deno_pinned_source_root_invalid' } }
        Assert-DenoHash (Join-Path $base ([string]$pinned.path)) ([string]$pinned.sha256)
    }
    $spdxIndex = Get-DenoSpdxIndex $SpdxRoot
    if ($spdxIndex.version -cne [string]$inputs.spdxLicenseList.version) { throw 'deno_spdx_version_mismatch' }

    $registryFallbackMap = @{}
    foreach ($fallback in $fallbacks.registryFallbacks) {
        if ($registryFallbackMap.ContainsKey([string]$fallback.id)) { throw "deno_fallback_duplicate:$($fallback.id)" }
        $registryFallbackMap[[string]$fallback.id] = $fallback
    }
    $workspaceFallbackMap = @{}
    foreach ($fallback in $fallbacks.workspaceFallbacks) {
        if ($workspaceFallbackMap.ContainsKey([string]$fallback.id)) { throw "deno_fallback_duplicate:$($fallback.id)" }
        $workspaceFallbackMap[[string]$fallback.id] = $fallback
    }
    $unresolvedMap = @{}
    foreach ($unresolved in $fallbacks.unresolved) { $unresolvedMap[[string]$unresolved.id] = $unresolved }

    $official = Read-DenoJson $OfficialMetadataPath
    $superset = Read-DenoJson $SupersetMetadataPath
    $officialIds = @(Get-DenoMetadataPackageIds $official)
    $supersetIds = @(Get-DenoMetadataPackageIds $superset)
    Assert-DenoTargetClosure -OfficialPackageIds $officialIds -SupersetPackageIds $supersetIds | Out-Null
    $officialSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $officialIds) { [void]$officialSet.Add($packageId) }
    $supersetSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $supersetIds) { [void]$supersetSet.Add($packageId) }

    $lockPackages = @(Read-DenoCargoLockPackages (Join-Path $DenoSourceRoot 'Cargo.lock'))
    $registryPackages = @($lockPackages | Where-Object { $_.source -like 'registry+*' })
    $workspacePackages = @($superset.packages | Where-Object { $null -eq $_.source })
    $vendorMap = @{}
    foreach ($directory in Get-ChildItem -LiteralPath $VendorRoot -Directory) {
        $toml = [IO.File]::ReadAllText((Join-Path $directory.FullName 'Cargo.toml'))
        $name = [regex]::Match($toml, '(?m)^name\s*=\s*"([^"]+)"').Groups[1].Value
        $version = [regex]::Match($toml, '(?m)^version\s*=\s*"([^"]+)"').Groups[1].Value
        $key = $name + "`0" + $version
        if ($vendorMap.ContainsKey($key)) { throw "deno_vendor_duplicate:$name@$version" }
        $vendorMap[$key] = $directory.FullName
    }
    if ($vendorMap.Count -ne $registryPackages.Count) { throw 'deno_vendor_lock_count_mismatch' }
    if (@(Get-ChildItem -LiteralPath $CrateArchiveRoot -Filter '*.crate' -File).Count -ne $registryPackages.Count) { throw 'deno_crate_archive_lock_count_mismatch' }

    $requiredNative = @($native.components | Where-Object { $_.required } | ForEach-Object { [string]$_.path })
    $observedNative = @($native.components | ForEach-Object { [string]$_.path })
    Assert-DenoNativeClosure -RequiredComponents $requiredNative -ObservedComponents $observedNative | Out-Null
    $nativeLicenseMap = @{}
    foreach ($component in $native.components | Where-Object { $_.path -ne 'v8' }) {
        $archive = Join-Path $NativeSourceRoot ([string]$component.archiveFile)
        $item = Get-Item -LiteralPath $archive
        if ($item.Length -ne [long]$component.length) { throw "deno_native_archive_length_mismatch:$($component.path)" }
        Assert-DenoHash $archive ([string]$component.sha256)
        $entries = @(& tar.exe -tzf $archive)
        if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) { throw "deno_native_archive_invalid:$($component.path)" }
        Assert-DenoUniquePaths @($entries | Where-Object { -not $_.EndsWith('/') }) | Out-Null
        $licenses = @($entries | Where-Object { (Split-Path $_ -Leaf) -match '^(?i:LICENSE|LICENCE|COPYING|NOTICE|PATENTS|COPYRIGHT)(?:[._-].*)?$' })
        if ($component.licenseRequired -and $licenses.Count -eq 0) { throw "deno_native_license_file_missing:$($component.path)" }
        $nativeLicenseMap[[string]$component.path] = @($licenses | Sort-Object -Unique)
    }

    $blockers = [Collections.Generic.List[string]]::new()
    $crateRecords = [Collections.Generic.List[object]]::new()
    foreach ($package in $registryPackages | Sort-Object name, version) {
        $id = $package.name + '@' + $package.version
        $key = $package.name + "`0" + $package.version
        if (-not $vendorMap.ContainsKey($key)) { $blockers.Add("deno_vendor_package_missing:$id"); continue }
        $crateArchive = Join-Path $CrateArchiveRoot ($package.name + '-' + $package.version + '.crate')
        if (-not (Test-Path -LiteralPath $crateArchive -PathType Leaf)) { $blockers.Add("deno_crate_archive_missing:$id"); continue }
        try {
            $fallback = if ($registryFallbackMap.ContainsKey($id)) { $registryFallbackMap[$id] } else { $null }
            $record = Assert-DenoCratePackage -Package $package -VendorPath $vendorMap[$key] -CrateArchivePath $crateArchive -SpdxRoot $SpdxRoot -UpstreamFallback $fallback -UpstreamSourceRoot $UpstreamSourceRoot
            $reason = if ($officialSet.Contains($id)) { 'official-workflow-profile' } elseif ($supersetSet.Contains($id)) { 'all-features-conservative-superset' } else { 'cargo-lock-conservative-superset' }
            $crateRecords.Add([ordered]@{ name = $package.name; version = $package.version; source = $package.source; sourceArchive = [ordered]@{ fileName = (Split-Path $crateArchive -Leaf); length = (Get-Item $crateArchive).Length; sha256 = $package.checksum; url = "https://static.crates.io/crates/$($package.name)/$($package.name)-$($package.version).crate" }; checksum = $package.checksum; license = $record.license; licenseFile = $record.licenseFile; repository = $record.repository; resolution = $record.resolution; resolvedLicenseFiles = $record.resolvedLicenseFiles; spdxLicenseIds = $record.spdxLicenseIds; spdxExceptionIds = $record.spdxExceptionIds; provenance = $record.provenance; inclusionReason = $reason })
        }
        catch {
            if ($unresolvedMap.ContainsKey($id)) { $blockers.Add("deno_upstream_license_unresolved:$id") }
            else { $blockers.Add($_.Exception.Message) }
        }
    }
    $workspaceRecords = [Collections.Generic.List[object]]::new()
    foreach ($package in $workspacePackages | Sort-Object name, version) {
        $id = ([string]$package.name) + '@' + ([string]$package.version)
        $manifestPath = [IO.Path]::GetFullPath([string]$package.manifest_path)
        $denoRoot = [IO.Path]::GetFullPath($DenoSourceRoot).TrimEnd('\') + '\'
        if (-not $manifestPath.StartsWith($denoRoot, [StringComparison]::OrdinalIgnoreCase)) { $blockers.Add("deno_workspace_manifest_outside_source:$id"); continue }
        $relativeManifest = $manifestPath.Substring($denoRoot.Length).Replace('\', '/')
        try {
            $license = [string]$package.license
            $resolution = $null
            $resolvedFiles = @()
            $spdxLicenseIds = @()
            $spdxExceptionIds = @()
            $provenance = $null
            if (-not [string]::IsNullOrWhiteSpace($license)) {
                $spdx = Resolve-DenoSpdxExpression -Expression $license -SpdxRoot $SpdxRoot
                $resolution = 'spdx-canonical-fallback'
                $resolvedFiles = @($spdx.files)
                $spdxLicenseIds = @($spdx.licenseIds)
                $spdxExceptionIds = @($spdx.exceptionIds)
                $provenance = [ordered]@{ spdxVersion = $spdx.version }
            }
            elseif ($workspaceFallbackMap.ContainsKey($id)) {
                $fallback = $workspaceFallbackMap[$id]
                $resolvedFiles = @($fallback.evidenceFiles | ForEach-Object {
                    $path = Join-Path $DenoSourceRoot ([string]$_.path)
                    Assert-DenoHash $path ([string]$_.sha256)
                    [ordered]@{ origin = 'pinned-workspace-source'; path = [string]$_.path; length = [long]$_.length; sha256 = [string]$_.sha256 }
                })
                $resolution = 'pinned-workspace-upstream-license'
                $license = [string]$fallback.resolvedLicense
                $provenance = $fallback
            }
            else { throw "deno_workspace_license_ambiguous:$id" }
            $reason = if ($officialSet.Contains($id)) { 'official-workflow-profile' } else { 'all-features-conservative-superset' }
            $workspaceRecords.Add([ordered]@{ name = [string]$package.name; version = [string]$package.version; source = "https://github.com/denoland/deno/tree/$($inputs.releaseIdentity.denoSourceCommit)/$($relativeManifest.Substring(0, $relativeManifest.LastIndexOf('/')))"; sourceManifest = [ordered]@{ path = $relativeManifest; length = (Get-Item $manifestPath).Length; sha256 = Get-DenoSha256 $manifestPath }; license = $license; licenseFile = [string]$package.license_file; repository = [string]$package.repository; resolution = $resolution; resolvedLicenseFiles = $resolvedFiles; spdxLicenseIds = $spdxLicenseIds; spdxExceptionIds = $spdxExceptionIds; provenance = $provenance; inclusionReason = $reason })
        }
        catch { $blockers.Add($_.Exception.Message) }
    }

    $counts = @{
        cargoLockPackages = $lockPackages.Count
        registryPackages = $registryPackages.Count
        resolvedRegistryPackages = $crateRecords.Count
        registryPackageFileResolutions = @($crateRecords | Where-Object resolution -ceq 'package-files').Count
        registrySpdxResolutions = @($crateRecords | Where-Object resolution -ceq 'spdx-canonical-fallback').Count
        registryUpstreamResolutions = @($crateRecords | Where-Object resolution -ceq 'upstream-commit-license-files').Count
        workspacePackages = $workspacePackages.Count
        resolvedWorkspacePackages = $workspaceRecords.Count
        workspaceSpdxResolutions = @($workspaceRecords | Where-Object resolution -ceq 'spdx-canonical-fallback').Count
        workspaceUpstreamResolutions = @($workspaceRecords | Where-Object resolution -ceq 'pinned-workspace-upstream-license').Count
        nativeComponents = @($native.components).Count
    }
    if ($blockers.Count -gt 0) {
        $reportPath = Write-DenoBlockerReport -ScratchRoot $ScratchRoot -Identity $identity -Blockers @($blockers) -Counts $counts -UnresolvedEvidence @($fallbacks.unresolved)
        throw "deno_collection_blocked:$($blockers.Count):$reportPath"
    }

    $outputRoot = Join-Path $ScratchRoot 'deno-third-party-output'
    if (Test-Path -LiteralPath $outputRoot) { throw 'deno_output_already_exists' }
    $stage = Join-Path $outputRoot 'bundle'
    $licenseRoot = Join-Path $stage 'LICENSES/cargo'
    $workspaceLicenseRoot = Join-Path $stage 'LICENSES/workspace'
    $nativeLicenseRoot = Join-Path $stage 'LICENSES/native'
    $sourceRoot = Join-Path $stage 'SOURCES'
    New-Item -ItemType Directory -Path $licenseRoot, $workspaceLicenseRoot, $nativeLicenseRoot, $sourceRoot | Out-Null
    $notice = [Text.StringBuilder]::new([IO.File]::ReadAllText((Join-Path $ManifestRoot 'THIRD-PARTY-NOTICES.template.txt')))
    $notice.Append("`n") | Out-Null
    $outputPaths = [Collections.Generic.List[string]]::new()
    foreach ($record in $crateRecords) {
        $safeId = ($record.name + '-' + $record.version) -replace '[^A-Za-z0-9._+-]', '_'
        $notice.AppendLine("=== $($record.name) $($record.version) ===").AppendLine("Source: $($record.sourceArchive.url)").AppendLine("Checksum: $($record.checksum)").AppendLine("Repository: $($record.repository)").AppendLine("License: $($record.license)").AppendLine("Resolution: $($record.resolution)").AppendLine("Inclusion: $($record.inclusionReason)") | Out-Null
        $vendorPath = $vendorMap[$record.name + "`0" + $record.version]
        foreach ($license in $record.resolvedLicenseFiles) {
            $destinationRelative = "LICENSES/cargo/$safeId/$($license.origin)/$($license.path)"
            $destination = Join-Path $stage $destinationRelative
            switch ([string]$license.origin) {
                'package' { New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null; Copy-Item -LiteralPath (Join-Path $vendorPath ([string]$license.path)) -Destination $destination }
                'spdx-license' { New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null; Copy-Item -LiteralPath (Join-Path $SpdxRoot ([string]$license.path)) -Destination $destination }
                'spdx-exception' { New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null; Copy-Item -LiteralPath (Join-Path $SpdxRoot ([string]$license.path)) -Destination $destination }
                'upstream-commit' { Copy-DenoZipEntry -ArchivePath (Join-Path $UpstreamSourceRoot ([string]$license.archiveFile)) -EntryPath ([string]$license.path) -Destination $destination }
                default { throw "deno_license_origin_invalid:$($license.origin)" }
            }
            Assert-DenoHash $destination ([string]$license.sha256)
            $outputPaths.Add($destinationRelative)
            $notice.AppendLine("--- $destinationRelative ---").AppendLine([IO.File]::ReadAllText($destination)).AppendLine() | Out-Null
        }
    }
    foreach ($record in $workspaceRecords) {
        $safeId = ($record.name + '-' + $record.version) -replace '[^A-Za-z0-9._+-]', '_'
        $notice.AppendLine("=== workspace $($record.name) $($record.version) ===").AppendLine("Source: $($record.source)").AppendLine("Manifest: $($record.sourceManifest.path)").AppendLine("License: $($record.license)").AppendLine("Resolution: $($record.resolution)").AppendLine("Inclusion: $($record.inclusionReason)") | Out-Null
        foreach ($license in $record.resolvedLicenseFiles) {
            $destinationRelative = "LICENSES/workspace/$safeId/$($license.origin)/$($license.path)"
            $destination = Join-Path $stage $destinationRelative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            if ([string]$license.origin -in @('spdx-license', 'spdx-exception')) { Copy-Item -LiteralPath (Join-Path $SpdxRoot ([string]$license.path)) -Destination $destination }
            elseif ([string]$license.origin -ceq 'pinned-workspace-source') { Copy-Item -LiteralPath (Join-Path $DenoSourceRoot ([string]$license.path)) -Destination $destination }
            else { throw "deno_license_origin_invalid:$($license.origin)" }
            Assert-DenoHash $destination ([string]$license.sha256)
            $outputPaths.Add($destinationRelative)
            $notice.AppendLine("--- $destinationRelative ---").AppendLine([IO.File]::ReadAllText($destination)).AppendLine() | Out-Null
        }
    }

    foreach ($rootLicense in @(Get-DenoLicenseFiles -Root $RustyV8SourceRoot)) {
        $relative = $rootLicense.FullName.Substring([IO.Path]::GetFullPath($RustyV8SourceRoot).TrimEnd('\').Length + 1).Replace('\', '/')
        $destinationRelative = "LICENSES/native/rusty_v8/$relative"
        $destination = Join-Path $stage $destinationRelative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $rootLicense.FullName -Destination $destination
        $outputPaths.Add($destinationRelative)
    }
    foreach ($v8License in @(Get-DenoLicenseFiles -Root $V8SourceRoot)) {
        $relative = $v8License.FullName.Substring([IO.Path]::GetFullPath($V8SourceRoot).TrimEnd('\').Length + 1).Replace('\', '/')
        $destinationRelative = "LICENSES/native/v8/$relative"
        $destination = Join-Path $stage $destinationRelative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $v8License.FullName -Destination $destination
        $outputPaths.Add($destinationRelative)
    }
    foreach ($component in $native.components | Where-Object { $_.path -ne 'v8' }) {
        $safeComponent = ([string]$component.path) -replace '[^A-Za-z0-9._+-]', '_'
        foreach ($entry in @($nativeLicenseMap[[string]$component.path])) {
            $destinationRelative = "LICENSES/native/$safeComponent/$entry"
            $destination = Join-Path $stage $destinationRelative
            Copy-DenoTarEntry -ArchivePath (Join-Path $NativeSourceRoot ([string]$component.archiveFile)) -EntryPath $entry -Destination $destination
            $outputPaths.Add($destinationRelative)
        }
    }
    Assert-DenoUniquePaths @($outputPaths) | Out-Null
    foreach ($artifact in $inputs.sourceArtifacts) {
        $source = [string]$artifactPaths[[string]$artifact.id]
        Copy-Item -LiteralPath $source -Destination (Join-Path $sourceRoot ([string]$artifact.fileName))
    }
    foreach ($component in $native.components | Where-Object { $_.path -ne 'v8' }) {
        Copy-Item -LiteralPath (Join-Path $NativeSourceRoot ([string]$component.archiveFile)) -Destination (Join-Path $sourceRoot ([string]$component.archiveFile))
    }
    $crateSourceRoot = Join-Path $sourceRoot 'cargo-crates'
    $upstreamSourceDestination = Join-Path $sourceRoot 'upstream-license-sources'
    New-Item -ItemType Directory -Path $crateSourceRoot, $upstreamSourceDestination | Out-Null
    foreach ($record in $crateRecords) { Copy-Item -LiteralPath (Join-Path $CrateArchiveRoot ([string]$record.sourceArchive.fileName)) -Destination (Join-Path $crateSourceRoot ([string]$record.sourceArchive.fileName)) }
    foreach ($archiveFile in @($fallbacks.registryFallbacks.archiveFile | Sort-Object -Unique)) { Copy-Item -LiteralPath (Join-Path $UpstreamSourceRoot $archiveFile) -Destination (Join-Path $upstreamSourceDestination $archiveFile) }
    $noticePath = Join-Path $outputRoot 'THIRD-PARTY-NOTICES.txt'
    Write-DenoUtf8Text $noticePath ($notice.ToString())
    Copy-Item -LiteralPath $noticePath -Destination (Join-Path $stage 'THIRD-PARTY-NOTICES.txt')
    Write-DenoUtf8Text (Join-Path $outputRoot 'component-manifest.json') (([ordered]@{ schemaVersion = 'deno-third-party-components/v2'; closureClassification = $inputs.closureClassification; releaseIdentity = $identity; spdxLicenseList = $inputs.spdxLicenseList; counts = $counts; crates = @($crateRecords); workspacePackages = @($workspaceRecords); nativeComponents = @($native.components); overallReleasePass = $false } | ConvertTo-Json -Depth 30) + "`n")
    $inventory = foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName) { [ordered]@{ path = $file.FullName.Substring($stage.Length + 1).Replace('\', '/'); length = $file.Length; sha256 = Get-DenoSha256 $file.FullName } }
    Write-DenoUtf8Text (Join-Path $outputRoot 'source-inventory.json') (([ordered]@{ schemaVersion = 'deno-source-inventory/v1'; files = @($inventory) } | ConvertTo-Json -Depth 10) + "`n")
    $zipPath = Join-Path $outputRoot 'deno-2.7.14-verified-conservative-superset-sources.zip'
    $zipSha256 = New-DenoDeterministicZip -SourceRoot $stage -ZipPath $zipPath
    return [pscustomobject]@{ status = 'complete'; closureClassification = $inputs.closureClassification; outputRoot = $outputRoot; noticePath = $noticePath; noticeSha256 = Get-DenoSha256 $noticePath; zipPath = $zipPath; zipSha256 = $zipSha256; counts = $counts; overallReleasePass = $false }
}

if ($Run) {
    $required = @($DenoSourceRoot, $RustyV8SourceRoot, $V8SourceRoot, $VendorRoot, $OfficialMetadataPath,
        $SupersetMetadataPath, $DenoExePath, $DenoSourceArchivePath, $RustyV8SourceArchivePath,
        $V8SourceArchivePath, $RustyV8StaticLibArchivePath, $NativeSourceRoot, $CrateArchiveRoot,
        $SpdxRoot, $SpdxArchivePath, $UpstreamSourceRoot, $UpstreamFallbackManifest, $ScratchRoot)
    if (@($required | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw 'deno_run_parameters_required' }
    Invoke-DenoThirdPartyNoticeCollection -ManifestRoot $ManifestRoot -DenoSourceRoot $DenoSourceRoot `
        -RustyV8SourceRoot $RustyV8SourceRoot -V8SourceRoot $V8SourceRoot -VendorRoot $VendorRoot `
        -OfficialMetadataPath $OfficialMetadataPath -SupersetMetadataPath $SupersetMetadataPath `
        -DenoExePath $DenoExePath -DenoSourceArchivePath $DenoSourceArchivePath `
        -RustyV8SourceArchivePath $RustyV8SourceArchivePath -V8SourceArchivePath $V8SourceArchivePath `
        -RustyV8StaticLibArchivePath $RustyV8StaticLibArchivePath -NativeSourceRoot $NativeSourceRoot `
        -CrateArchiveRoot $CrateArchiveRoot -SpdxRoot $SpdxRoot -SpdxArchivePath $SpdxArchivePath `
        -UpstreamSourceRoot $UpstreamSourceRoot -UpstreamFallbackManifest $UpstreamFallbackManifest `
        -ScratchRoot $ScratchRoot
}
